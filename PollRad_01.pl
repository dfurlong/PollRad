#!/usr/bin/perl
#PollRad.pl

################################################################################
# DESCRIPTION:
#
#   The following is the main program for polling a RAD TDM device in order
#   to reset the jitter buffer when it excceeds a maximum threshold.
#
################################################################################
# COPYRIGHT:  CONFIDENTIAL
#
#             Copyright (c) 2010
#             Amperion Inc.
#             ALL RIGHTS RESERVED
#
#             Unauthorized access to, copying, use of or disclosure of this
#             software, or any of its features, is strictly prohibited. Your
#             access to or possession of a copy of this software is pursuant to
#             a limited license; ownership of the software and any associated
#             media remain with Amperion Inc.
#
# USAGE:
#		To start the program enter the command below and replace IPAddress
#		with the dot decmial notation equivelant (i.e. 168.192.20.63).
#
#			perl PollRad.pl "IPAddress"
#
# REQUIRES:
#		NET::SNMP  version 6.0.1
#		NET::TELNET  version 3.03
#
# INSTALLATION:
#		To install the Net::SNMP module and Net:TELNET module and all of
#		it's dependencies directly from the Comprehensive Perl Archive
#		Network (CPAN) execute the commands:
#
#			cpan
#			install Net::SNMP
#			install Net::Telenet
#
# REVISION HISTORY
#
#	Rev 0.1 Oct 8, 2010	First release to AEP for field testing.
#
################################################################################

use warnings;

use Net::Telnet ();
use Net::SNMP;

$aboutProgram = "Perl script PollRad.pl  (Rev 0.1 Oct 08, 2010)   Copywrite (c) 2010 Amperion Inc.";

					# Declare Global Constants
$IPAddress = shift @ARGV;		# From command line, IP address of RAD device to be polled
$jitterValue = 18.0;			# Center of Jitter Value Setting
$threshold = $jitterValue + 5.0;	# Set Threshold to test Max Jitter Value against
$loopWaitPeriod = 15;			# Defines Loop wait period in seconds
$logOffWaitPeriod = 5;			# Defines wait period after TELNET logoff

$username = "su";			# TELNET Username
$password = "1234";			# TELNET Password
$writeCommunity="private";              # SNMP write community string

					# Define OID values
$OID_CurrentStatMaxJittBufLevel = '1.3.6.1.4.1.164.3.1.6.7.10.1.6.101';
$OID_JitterBuffer = '1.3.6.1.4.1.164.3.1.6.7.1.1.9.101';


                                        # Declare Global Variables
$currJitterBufferSetting = 0.0;		# Current Jitter Buffer Setting
$lastJitterValue = 0.0;			# Last Jitter Value Set
$maxJitterValue = 0;			# Set Default for Max Jitter Value
$logFile = "";				# LogFile

print $aboutProgram, "\n\n";
print "Started Polling RAD device at IP Address = $IPAddress  [ ", DisplayTime(), " ] \n\n";

CreateLogFileName();

open LOGFILE, "> $logFile" or die $!;              #Create new file
print LOGFILE $aboutProgram, "\n\n";
print LOGFILE "Started Polling RAD device at IP Address = $IPAddress  [ ", DisplayTime(), " ] \n\n";    #Print to log file
close LOGFILE;

ClearMaxJitterValue();

#SetJitterValueSNMP();   #Commented Out, This forces a reset to be needed

################################################################################
#
# This is the main while loop for the infinite polling loop
#
################################################################################

while (1) {

	GetValuesSNMP();
	#GetMaxJitterValue();                       # Note this is Commented Out

	if($maxJitterValue > $threshold) {
		ClearMaxJitterValue();
		GetValuesSNMP();
		#GetMaxJitterValue();               # Note: this is commented out

		if($maxJitterValue > $threshold) {
			ChangeJitterValueSNMP();
			#ChangeJitterValue();       # Note: this is commented out
			LogEvent();
			ClearMaxJitterValue();
		}
	}

	sleep($loopWaitPeriod);
}

################################################################################
#
# DisplayTime Function
#
################################################################################
sub DisplayTime {

	@months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	@weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);

	($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();

	$year = 1900 + $yearOffset;

	$hourStr = sprintf("%02d",$hour);			#Convert to string
	$minuteStr = sprintf("%02d",$minute);			#Convert to string
	$secondStr = sprintf("%02d",$second);			#Convert to String
	$dayOfMonthStr = sprintf("%02d",$dayOfMonth);		#Convert to String

	$timeStr = "$hourStr:$minuteStr:$secondStr, $weekDays[$dayOfWeek] $months[$month] $dayOfMonthStr, $year";
	return $timeStr;
}

################################################################################
#
# CreateLogFileName Function
#
################################################################################
sub CreateLogFileName {

	@months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	@weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);

	($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();

	$year = 1900 + $yearOffset;

	$hourStr = sprintf("%02d",$hour);			#Convert to string
	$minuteStr = sprintf("%02d",$minute);			#Convert to string
	$secondStr = sprintf("%02d",$second);			#Convert to String
	$monthStr = sprintf("%02d",$month);                     #Convert to string
	$dayOfMonthStr = sprintf("%02d",$dayOfMonth);		#Convert to String

	$logFile = "LogFile\_$year\_$monthStr\_$dayOfMonthStr\_$hourStr\_$minuteStr\_$secondStr.log";

}



################################################################################
#
# ClearMaxJitterValue Function
#
################################################################################
sub ClearMaxJitterValue {
	$maxJitterValue = 0;


	$t = new Net::Telnet (Errmode => 'return');	# Create Telnet Object

	$t->open($IPAddress);				# Open Connection

	$t->waitfor('/PASSWORD:.*$/');			# Wait for PASSWORD to appear

	$t->print("$username");         		# Issue Username

	$t->waitfor('/su.*$/');				# Wait for Username Echo to return

	$t->print("$password");				# Issue Password

	$t->waitfor('/Please.*$/');			# Wait for Please to appear

	$t->print("3");					# Select Monitor = 3

	$t->waitfor('/Please.*$/');			# Wait for Please to appear

	$t->print("3");					# Select Connection = 3

	$t->waitfor('/Please.*$/');			# Wait for Please to appear

	$t->print("C");					# Issue Clear Command

	$t->waitfor('/Please.*$/');			# Wait for Please to appear

	$t->print("\cX");				# Log off <cntl>x

	$t->close;					# Distroy Telent Object

	sleep($logOffWaitPeriod);			# Time delay after logoff
}

################################################################################
#
# LogEvent Function
#
################################################################################
sub LogEvent {
	print ("MaxJitter = $maxJitterValue  Exceeds $threshold,  Buffer Changed to $lastJitterValue [ ", DisplayTime(), " ] \n\n");

	open LOGFILE, ">> $logFile" or die $!;
	print LOGFILE ("MaxJitter = $maxJitterValue  Exceeds $threshold,  Buffer Changed to $lastJitterValue  [ ", DisplayTime(), " ] \n\n");
	close LOGFILE;

}

################################################################################
#
# GetValuesSNMP Function
#
################################################################################
sub GetValuesSNMP {

	# Define Default value if communication error occurs

	$maxJitterValue = 0;
	$currJitterBufferSetting = 0;

	# Create SNMP Session
	my ($session, $error) = Net::SNMP->session(-hostname=>$IPAddress);

	# Get MaxJitterBuffer value
	my $result = $session->get_request(-varbindlist => [ $OID_CurrentStatMaxJittBufLevel ],);

	if(!defined $result) {
		print ("SNMP ERROR: ", $session->error(),"  [ ", DisplayTime() ," ]\n");

		open LOGFILE, ">> $logFile" or die $!;
		print LOGFILE ("SNMP ERROR: ", $session->error(),"  [ ", DisplayTime() ," ]\n");
		close LOGFILE;

		$session->close();
		return;
	}

	$maxJitterValue = $result->{$OID_CurrentStatMaxJittBufLevel};

	# Get JitterBuffer Setting
	my $result_1 = $session->get_request(-varbindlist => [ $OID_JitterBuffer ],);

	if(!defined $result_1) {
		print ("SNMP ERROR: ", $session->error(),"  [ ", DisplayTime() ," ]\n");

		open LOGFILE, ">> $logFile" or die $!;
		print LOGFILE ("SNMP ERROR: ", $session->error(),"  [ ", DisplayTime() ," ]\n");
		close LOGFILE;

		$session->close();
		return;
	}

	$currJitterBufferSetting = ($result_1->{$OID_JitterBuffer})/100;

	print ("SNMP MaxJitterBufferLevel = $maxJitterValue   JitterBufferSetting = $currJitterBufferSetting  [ ", DisplayTime(), " ] \n\n");

	#Close SNMP session
	$session->close();

}

################################################################################
#
# ChangeJitterValueSNMP Function
#
################################################################################
sub ChangeJitterValueSNMP {

	my $newValue;

	if($currJitterBufferSetting > $jitterValue){
		$newValue = ($jitterValue - 0.25)*100;

	}
	else {
		$newValue = ($jitterValue + 0.25)*100;
	}

	my ($session, $error) = Net::SNMP->session(-hostname=>$IPAddress,
	                                           -community=>$writeCommunity);

	my $result = $session->set_request(-varbindlist => [ $OID_JitterBuffer, INTEGER, $newValue ],);

	$lastJitterValue = $newValue/100;           # Scale to msec for display purposes

	if(!defined $result) {
		print ("SNMP SET ERROR: ", $session->error(),"  [ ", DisplayTime() ," ]\n");

		open LOGFILE, ">> $logFile" or die $!;
		print LOGFILE ("SNMP SET ERROR: ", $session->error(),"  [ ", DisplayTime() ," ]\n");
		close LOGFILE;

	}

	$session->close();

}
################################################################################
#
#  NOTE:
#
#      The following functions where used during the development of the program
#      and are not used in the final version.
#
#
################################################################################
#
# SetJitterValueSNMP Function
#
################################################################################
sub SetJitterValueSNMP {


	my ($session, $error) = Net::SNMP->session(-hostname=>$IPAddress,
	                                           -community=>$writeCommunity);

	my $result = $session->set_request(-varbindlist => [ $OID_JitterBuffer, INTEGER, '2000' ],);

	if(!defined $result) {
		print ("SNMP SET ERROR: ", $session->error(),"  [ ", DisplayTime() ," ]\n");

		open LOGFILE, ">> $logFile" or die $!;
		print LOGFILE ("SNMP SET ERROR: ", $session->error(),"  [ ", DisplayTime() ," ]\n");
		close LOGFILE;

	}

	$session->close();

}

################################################################################
#
# GetMaxJitterValue Function
#
################################################################################
sub GetMaxJitterValue {

	$t = new Net::Telnet (Errmode => 'return');	# create Telnet Object

	$t->open($IPAddress);				# Open Connection

	$t->waitfor('/PASSWORD:.*$/');

	$t->print("$username");     			# Issue Username

	$t->waitfor('/su.*$/');

	$t->print("$password");				# Issue Password

	$t->waitfor('/Please.*$/');

	$t->print("3");					# Select Monitor = 3

	$t->waitfor('/Please.*$/');

	$t->print("3");					# Select Connection = 3

	@lines = $t->waitfor('/Please.*$/');
	my @fields = split /Max Jitter/, $lines[0];
	my @fields1 = split /Total/, $fields[2];
	my @fields2 = split /\(/, $fields1[0];
	my @fields3 = split /\)/, $fields2[1];
	$maxJitterValue = $fields3[0];

	$t->print("\cX");				# Logoff <cntl-x>

	$t->close;					# Distroy Object

	sleep($logOffWaitPeriod);

	print ("TELNET  MaxJitter = $maxJitterValue at  ( ", DisplayTime(), " ) \n\n");

}

################################################################################
#
# ChangeJitterValue Function
#
################################################################################
sub ChangeJitterValue {

	if($lastJitterValue > $jitterValue){
		$lastJitterValue = $jitterValue - 0.25;
	} else {
		$lastJitterValue = $jitterValue + 0.25;
	}



	$t = new Net::Telnet (Errmode => 'return');	# create Telnet Object

	$t->open($IPAddress);				# Open Connection

	$t->waitfor('/PASSWORD:.*$/');

	$t->print("$username");    			# Issue Username

	$t->waitfor('/su.*$/');

	$t->print("$password");				# Issue Password

	$t->waitfor('/Please.*$/');

	$t->print("2");					# Select Configuration = 2

	$t->waitfor('/Please.*$/');

	$t->print("4");					# Select Connection = 4

	$t->waitfor('/Please.*$/');

	$t->print("4");					# Select Bundle Connection = 4

	$t->waitfor('/Please.*$/');

	$t->print("N");					# Select Next Screen = N

	$t->waitfor('/Please.*$/');

	$t->print("2");					# Select JitterBuffer= 2

	$t->waitfor('/Please.*$/');

	$t->print($lastJitterValue);			# Write New Value to set Jitter Buffer

	$t->waitfor('/Please.*$/');

	$t->print("S");					# Issue Save

	$t->waitfor('/Please.*$/');

	$t->print("\cX");				# Logoff <cntl-x>

	$t->close;					# Distroy Object

	sleep($logOffWaitPeriod);
}
