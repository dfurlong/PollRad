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
#			install Net::Telnet
#
# REVISION HISTORY
#
#	Rev 0.1 Oct  8, 2010	First release to field for testing.
#	Rev 0.2 Oct 13, 2010    Added reading of MinJitterBuff Level,
#				Minimized writing to the log file
#	Rev 0.3 Oct 21, 2010    Added elapsed time between Jitter reset events
#				Only write to log file for Jitter Reset events
#				Minimized writing to the console
#	Rev 0.4	Dec 17, 2010	Added optional input field for location in output file name
#
################################################################################

use warnings;

use Net::Telnet ();
use Net::SNMP;

$aboutProgram = "Perl script PollRad.pl  (Rev 0.3 Oct 21, 2010)   Copywrite (c) 2010 Amperion Inc.";

# Declare Global Constants
$IPAddress = "";
$LocationText = "";
if(scalar(@ARGV) > 0){
	$IPAddress = shift @ARGV;		# From command line, IP address of RAD device to be polled
}
else{
	die("Input Error! Need to provide target IP Address");
}

if(scalar(@ARGV) > 0){
	$LocationText = "\_" . shift @ARGV;		# From command line, text appended into output file name
}


$jitterValue = 40.0;		   		# Center of Jitter Value Setting
$threshold = $jitterValue + 7.0;	# Set Threshold to test Max Jitter Value against
$loopWaitPeriod = 15;				# Defines Loop wait period in seconds
$logOffWaitPeriod = 5;		   		# Defines wait period after TELNET logoff

$username = "su";					# TELNET Username
$password = "1234";					# TELNET Password
$writeCommunity="private";          # SNMP write community string

					# Define OID values

$OID_CurrentStatMinJittBufLevel 	= '1.3.6.1.4.1.164.3.1.6.7.10.1.5.101';
$OID_CurrentStatMaxJittBufLevel 	= '1.3.6.1.4.1.164.3.1.6.7.10.1.6.101';
$OID_JitterBuffer 			= '1.3.6.1.4.1.164.3.1.6.7.1.1.9.101';


                                        # Declare Global Variables
$currJitterBufferSetting = 0.0;		# Current Jitter Buffer Setting
$lastJitterValue = 0.0;			# Last Jitter Value Set
$lastMaxJitterValue = 0.0;		# Last Max Jitter Value Read
$lastMinJitterValue = 0.0;		# Last Min Jitter Value Read
$maxJitterValue = 0;			# Set Default for Max Jitter Value
$minJitterValue = 100;			# Set Default for Min Jitter Value
$logFile = "";					# LogFile
$commState = 'True';            # Boolean variable set to true, default communications established.
$lastUpdateTime = time;			# Set to program start time;


print $aboutProgram, "\n\n";
print "Started Polling RAD device at IP Address = \"$IPAddress\"  [ ", CreateTimeString(time), " ] \n";
print "Buffer Set Point = $jitterValue,  Threshold = $threshold\n\n";

CreateLogFileName();

open LOGFILE, ">> $logFile" or die $!;              #Create new file if it does not allready exist
print LOGFILE $aboutProgram, "\n\n";
print LOGFILE "Started Polling RAD device at IP Address = \"$IPAddress\"  [ ", CreateTimeString(time), " ] \n";    #Print to log file
print LOGFILE "Buffer Set Point = $jitterValue,  Threshold = $threshold\n\n";
close LOGFILE;

# Clear values in device before polling starts
ClearMaxJitterValue();


################################################################################
#
# This is the main while loop for the infinite polling loop
#
################################################################################

while (1) {

	GetValuesSNMP();

	if($maxJitterValue > $threshold) {
		ClearMaxJitterValue();
		GetValuesSNMP();

		if($maxJitterValue > $threshold) {
			ChangeJitterValueSNMP();
			LogEvent();
			ClearMaxJitterValue();
		}
	}

	sleep($loopWaitPeriod);
}


################################################################################
#
# CreateTimeString Function
#
################################################################################
sub CreateTimeString {

	my($timeValue) = @_;                                   # 1 Passed Argument

	@months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	@weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);

	($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime($timeValue);

	$year = 1900 + $yearOffset;

	$hourStr = sprintf("%02d",$hour);			#Convert to string
	$minuteStr = sprintf("%02d",$minute);			#Convert to string
	$secondStr = sprintf("%02d",$second);			#Convert to String
	$dayOfMonthStr = sprintf("%02d",$dayOfMonth);		#Convert to String

        #$timeStr = "$hourStr:$minuteStr:$secondStr, $weekDays[$dayOfWeek] $months[$month] $dayOfMonthStr, $year";

	$timeStr = "$weekDays[$dayOfWeek] $months[$month] $dayOfMonthStr, $year; $hourStr:$minuteStr:$secondStr";
	return $timeStr;
}

################################################################################
#
# TimeDiffString Function
#
################################################################################
sub TimeDiffString {
	my($arg1, $arg2) = @_;           # Pass time arguments to function

	my $timeDiff = abs($arg1-$arg2); # Calculate time difference

	my $secInDay = 60 * 60 * 24;    # Number of Seconds in one day = 60 Seconds * 60 Minutes * 24 Hours
	my $secInHour = 60 * 60;        # Number of seconds in one hour
	my $secInMinute = 60;           # Number of seconds in one minute

	my $days = int($timeDiff / $secInDay);

        $timeDiff = $timeDiff - $days * $secInDay;
	my $hours = int($timeDiff / $secInHour);

        $timeDiff = $timeDiff - $hours * $secInHour;
        my $minutes = int($timeDiff / $secInMinute);

        my $seconds = $timeDiff - $minutes * $secInMinute;

        my $timeDiffString = "$days". "d:" .  sprintf("%02d",$hours) . "h:" . sprintf("%02d",$minutes) . "m:" . sprintf("%02d",$seconds). "s";

        return $timeDiffString;

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
	$monthStr = sprintf("%02d",$month +1 );                     #Convert to string
	$dayOfMonthStr = sprintf("%02d",$dayOfMonth);		#Convert to String

	$logFile = "PollRad" . $LocationText . "\_$monthStr$dayOfMonthStr.log";

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

	my $eventTime = time;

	print ("MaxJitter = $maxJitterValue  Exceeds $threshold,  Buffer Changed to $lastJitterValue [ ",
        CreateTimeString($eventTime), " ]  (+", TimeDiffString($lastUpdateTime, $eventTime), ") \n\n");

	open LOGFILE, ">> $logFile" or die $!;
	print LOGFILE ("MaxJitter = $maxJitterValue  Exceeds $threshold,  Buffer Changed to $lastJitterValue  [ ",
        CreateTimeString($eventTime), " ]  (+", TimeDiffString($lastUpdateTime, $eventTime), ")\n\n");

        close LOGFILE;

        $lastUpdateTime = $eventTime;

}

################################################################################
#
# GetValuesSNMP Function
#
################################################################################
sub GetValuesSNMP {

	# Define Default value if communication error occurs

	$maxJitterValue = 0;
        $minJitterValue = 0;
	$currJitterBufferSetting = 0;

	# Create SNMP Session
	my ($session, $error) = Net::SNMP->session(-hostname=>$IPAddress);

	# Get MinJitterBuffer value
	my $result = $session->get_request(-varbindlist => [ $OID_CurrentStatMinJittBufLevel ],);

	if(!defined $result) {
		print ("SNMP ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");

                if($commState){
         		$lastMaxJitterValue = 0;
                	$lastMinJitterValue = 0;
                	$commState = '';

  			open LOGFILE, ">> $logFile" or die $!;
			print LOGFILE ("SNMP ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");
			close LOGFILE;
                }

		$session->close();
		return;
	}

	$minJitterValue = $result->{$OID_CurrentStatMinJittBufLevel};


       # Get MaxJitterBuffer value
	my $result_1 = $session->get_request(-varbindlist => [ $OID_CurrentStatMaxJittBufLevel ],);

	if(!defined $result_1) {
		print ("SNMP ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");

                if($commState){
               		$lastMaxJitterValue = 0;
                	$lastMinJitterValue = 0;
                	$commState = '';

    			open LOGFILE, ">> $logFile" or die $!;
			print LOGFILE ("SNMP ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");
			close LOGFILE;
                }

		$session->close();
		return;
	}

	$maxJitterValue = $result_1->{$OID_CurrentStatMaxJittBufLevel};


      # Get JitterBuffer Setting
	my $result_2 = $session->get_request(-varbindlist => [ $OID_JitterBuffer ],);

	if(!defined $result_2) {
		print ("SNMP ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");

                if($commState){
                	$commState = '';              #Set to false
           		$lastMaxJitterValue = 0;
                	$lastMinJitterValue = 0;

                        open LOGFILE, ">> $logFile" or die $!;
			print LOGFILE ("SNMP ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");
			close LOGFILE;
                }

		$session->close();
		return;
	}

        $commState = 'True';                                               #Set to true, communication exists
	$currJitterBufferSetting = ($result_2->{$OID_JitterBuffer})/100;

        my $minString = sprintf("%2s", $minJitterValue);                   # Convert to two character string
        my $maxString = sprintf("%2s", $maxJitterValue);                   # Convert to two character string

	#print ("SNMP BufferLevel (min, max) =  $minString, $maxString;   BufferSetting = $currJitterBufferSetting  [ ", CreateTimeString(time), " ] \n\n");

        # If the value(s) have changed write message to logfile and console.
        if($lastMaxJitterValue != $maxJitterValue or $lastMinJitterValue != $minJitterValue){
        	$lastMaxJitterValue = $maxJitterValue;
                $lastMinJitterValue = $minJitterValue;

        	print ("BufferLevel (min, max) =  $minString, $maxString;   BufferSetting = $currJitterBufferSetting  [ ", CreateTimeString(time), " ] \n\n");

                #open LOGFILE, ">> $logFile" or die $!;
		#print LOGFILE ("BufferLevel (min, max) =  $minString, $maxString;   BufferSetting = $currJitterBufferSetting  [ ", CreateTimeString(time), " ] \n\n");
		#close LOGFILE;
        }

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
		print ("SNMP SET ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");

		open LOGFILE, ">> $logFile" or die $!;
		print LOGFILE ("SNMP SET ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");
		close LOGFILE;

	}

	$session->close();

}
################################################################################
#
#  NOTE:
#
#      The following function(s) where used during the development of the program
#      and are not intended to be used in the final version.
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

       #Set Jitter Buffer t0 20.00ms
	my $result = $session->set_request(-varbindlist => [ $OID_JitterBuffer, INTEGER, '2000' ],);

	if(!defined $result) {
		print ("SNMP SET ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");

		open LOGFILE, ">> $logFile" or die $!;
		print LOGFILE ("SNMP SET ERROR: ", $session->error(),"  [ ", CreateTimeString(time) ," ]\n");
		close LOGFILE;

	}

	$session->close();

}


