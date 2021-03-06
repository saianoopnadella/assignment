#!/usr/bin/perl
use DBI;
use Net::SNMP qw(:ALL);
use FindBin qw($Bin);

@split = split("/",$Bin);
pop(@split);
push(@split,"db.conf");
$realpath = join("/",@split);
require $realpath;
# A simple trap handler

my $filename = "$Bin/traps.log";
open(my $fh, '>>', $filename) or die "Could not open file '$filename' $!";


my $host = <STDIN>; 
chomp($host);
my $ip = <STDIN>;	# Read the IP - Second line of input
 chomp($ip);
$date = `date`;
chomp($date);
while(<STDIN>) {
        chomp($_);
        push(@vars,$_);
}
    say $fh "New trap received: $date for \nHOST: $host\nIP: $ip\n";
foreach(@vars) {
        say $fh "TRAP: $_\n";
}
say $fh "\n----------\n";

#---------------------------------------- finding fqdn and status

foreach(@vars) 
{
my @trap;
@trap=split(' ',$_);
if ($trap[0] eq "iso.3.6.1.4.1.41717.10.1")
{
@ele=split('"',$trap[1]);
$FQDN=$ele[1];
}

if ($trap[0] eq "iso.3.6.1.4.1.41717.10.2"){
$status=$trap[1];
}
}
#-------------------------------------database connection

$date=time();	
$dbh = DBI -> connect ("dbi:mysql:$database:$host:$port", $username, $password) or die;

my $sth1 =$dbh->prepare("SELECT IP,PORT,COMMUNITY FROM trap_alert");
$sth1->execute() or die $DBI::errstr;
my @manager= $sth1->fetchrow_array();
my ($IP,$PORT,$COMMUNITY) = @manager;
my $sth = $dbh->prepare("SELECT ID, FQDN, PrevStatus, CurrentStatus, PrevTime, CurrentTime FROM trap_db");
$sth->execute() or die $DBI::errstr;

$n=0;
while (my @data = $sth->fetchrow_array()) 
{
   my ($id, $fqdn, $PrevStatus, $CurrentStatus, $PrevTime, $CurrentTime) = @data;
	#print file "$fqdn";
	if($fqdn eq $FQDN)
	{
	$n++;
	my $sth1 = $dbh->prepare("UPDATE trap_db
                        SET `PrevStatus` ='$CurrentStatus', `CurrentStatus`='$status', `PrevTime`='$CurrentTime', `CurrentTime`='$date'  
                        WHERE `FQDN` = '$fqdn'");
	$sth1->execute() or die $DBI::errstr;
	$sth1->finish();
	next;	
	}	
}

#---------------------------new trap received

if($n==0)
{
my $sth = $dbh->prepare("INSERT INTO trap_db (FQDN, CurrentStatus, CurrentTime) values('$FQDN','$status','$date')");
	$sth->execute() or die $DBI::errstr;
	$sth->finish();	
}

#-----------------------session for fail trap

if($status eq 3) 
{
my $sth = $dbh->prepare("SELECT ID, FQDN, PrevStatus, CurrentStatus, PrevTime, CurrentTime FROM trap_db WHERE `FQDN` = '$FQDN'");
$sth->execute() or die $DBI::errstr;
my @data = $sth->fetchrow_array();
my ($id, $fqdn, $PrevStatus, $CurrentStatus, $PrevTime, $CurrentTime) = @data;
my $oid1= '1.3.6.1.4.1.41717.20';
my ($session, $error) = Net::SNMP->session(
		 -hostname    => $IP,
		 -port	       => $PORT,
		 -community   => $COMMUNITY,
		 	      );
my @array1 = qw();
print"$IP $COMMUNNITY";
push (@array1,"$oid1.1", OCTET_STRING, $fqdn);
push (@array1,"$oid1.2", INTEGER32, $CurrentTime);
push (@array1,"$oid1.3", INTEGER, $PrevStatus);
push (@array1,"$oid1.4", INTEGER32, $PrevTime);

print"@array1";
my $result = $session->trap(
                 -varbindlist      => \@array1,
                       );

}

$sth->finish();


#------------------------------------fqdn for danger trap
if ($status eq 2)
{
 my $oid= '1.3.6.1.4.1.41717.30';

my $sth = $dbh->prepare("SELECT ID, FQDN, PrevStatus, CurrentStatus, PrevTime, CurrentTime FROM trap_db");
$sth->execute() or die $DBI::errstr;
my $counter='0';
my $end='1';
my @array = qw();
while (my @row = $sth->fetchrow_array()) 

{
	
my ($id, $fqdn, $Prev_Status, $CurrentStatus) = @row;
	if($CurrentStatus eq 2)
	{
	$counter++;}
}
my $sth = $dbh->prepare("SELECT ID, FQDN, PrevStatus, CurrentStatus, PrevTime, CurrentTime FROM trap_db");
$sth->execute() or die $DBI::errstr;

if($counter ge 2)
{
	while (my @row1 = $sth->fetchrow_array()) 

	{
	   my ($id, $fqdn, $PrevStatus, $CurrentStatus, $PrevTime, $CurrentTime) = @row1;
              
	   if($CurrentStatus eq 2)
	{
if($PrevStatus eq '')
		{
		$PrevStatus="8";
		$PrevTime="0";	
		}
	   push (@array,"$oid.$end",OCTET_STRING, "$fqdn");
		$end++;
		push (@array,"$oid.$end",INTEGER32, "$CurrentTime");
		$end++;
		push (@array,"$oid.$end",INTEGER, "$PrevStatus");
		$end++;
		push (@array,"$oid.$end",INTEGER32, "$PrevTime");
		$end++;
			
	   }	

print "@array";

}

my ($session, $error) = Net::SNMP->session(
		 -hostname    => $IP,
		 -port	       => $PORT,
		 -community   => $COMMUNITY,	 
	      );
 
my $result = $session->trap(
                 -varbindlist      => \@array
                       );
if (!defined $result) {
      printf "ERROR: %s\n", $session->error();
      $session->close();
      exit 1;
	}

}
}
close $fh;
