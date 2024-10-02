# $Id: GeoExperiment.pm 9600 2009-10-29 14:38:30Z farne $

package EBI::FGPT::Converter::GEO::GeoExperiment;

use LWP::Simple qw($ua get);
use XML::XPath;
use HTTP::Status;
use File::Spec;
use File::Temp qw(tempfile);
use Carp;
use EBI::FGPT::Converter::GEO::Config qw(get_config);
use Data::Dumper;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT_OK = qw(gse_to_gds get_SRA_study_accs_for_GSE);

use Log::Log4perl;
my $logger = Log::Log4perl::get_logger("SOFT");

use EBI::FGPT::Config qw($CONFIG);
if ( my $proxy = $CONFIG->get_HTTP_PROXY ) {
	$ua->proxy( ['http'], $proxy );
}

{    # Read the GSE to GDS map file in once, and cache the results.
	my $gse_gds_map;

	sub gse_to_gds {

		my ($accession) = @_;

		unless ($gse_gds_map) {

			$gse_gds_map = {};

			# Get a list of GDS for each GSE.
			my $map_file = get_config('gse_gds_map_file');
			open( my $map_fh, '<', $map_file )
			  or croak("ERROR: Unable to open map file $map_file: $!");

		  LINE:
			while ( defined( my $line = <$map_fh> ) ) {
				chomp($line);
				my ( $line_accession, $gds_count, @accns ) = split( '\t', $line );
				$gse_gds_map->{$line_accession} = [ map { "GDS$_" } @accns ];
			}
			close($map_fh);
		}

		return ( $gse_gds_map->{$accession} || [] );
	}

}    # End of $gse_gds_map scope.



sub get_SRA_study_accs_for_GSE {
	my ($gse) = @_;

	my $eutils_uri = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/";

	# Get uid for GSE
	my $gse_uid = get_gse_uid( $gse, $eutils_uri ) or return;

	# link GSE uid to SRA uids
	my $sra_links = get_sra_links( $gse_uid, $eutils_uri ) or return;

	# get SRA study accs for uids
	my %studies;
	foreach my $sra_uid ( @{$sra_links} ) {
		my $acc = get_sra_study( $sra_uid, $eutils_uri );
		$studies{$acc}++ if $acc;
	}

	my @list = keys %studies;
	my $list = join( "\n", @list );
	$logger->info("The following SRA study accessions were found for $list");

	return \@list;

}

sub get_gse_uid {

	my ( $gse, $eutils_uri ) = @_;

	$logger->info("Querying NCBI for $gse");

	my $id;

	my $gse_result =
	  get(  $eutils_uri
		  . "esearch.fcgi?db=gds&term="
		  . $gse
		  . "[acc]+AND+GSE[ETYP]&retmode=xml" );
	if ($gse_result) {

		$_ = $gse_result;
		my @uids = /<Id>(\d*)<\/Id>/ig;
		if (@uids) {
			if ( scalar @uids > 1 ) {
				$gse =~ /GSE(\d*)/gixms;
				my ($matching_id) = grep /$1/, @uids;
				$id = $matching_id || $uids[0];
			}
			else {
				$id = $uids[0];
			}
		}
		else {
			$logger->warn("Warning: no UIDs found for $gse");
		}
	}
	else {
		$logger->warn("Warning: could not get results for eutils search for $gse");
	}

	return $id;
}

sub get_sra_links {

	my ( $uid, $eutils_uri ) = @_;

	$logger->info("Querying NCBI for SRA IDs linked to GSE UID $uid");

	my @links;
	my $link_result = get( $eutils_uri . "elink.fcgi?dbfrom=gds&db=sra&id=$uid" );

	if ($link_result) {
		$_     = $link_result;
		@links = /<Link>[^<]*<Id>(\d*)<\/Id>[^<]*<\/Link>/igs;
	}
	else {
		$logger->warn(
			"Warning: could not get results for eutils link search for GSE UID $uid");
	}

	if (@links) {
		return \@links;
	}
	else {
		$logger->warn("Warning: no SRA links found for GSE UID $uid");
		return undef;
	}
}

sub get_sra_study {

	my ( $uid, $eutils_uri ) = @_;

	my $acc;
	my $summary = get_sra_summary( $uid, $eutils_uri ) or return;

	my $study_accs;

	if ( $summary =~ /(.)+(SRP([0-9])*)(.)+/ ) {
		$study_accs = $2;
	}

	if ($study_accs) {
		$logger->info("SRA study accession found for $uid, returning first result");
		$acc = $study_accs;
	}
	else {
		$logger->warn("No SRA study accessions found for UID $uid");
	}

	return $acc;

}

sub get_sra_summary {

	my ( $uid, $eutils_uri ) = @_;

	my $summary = get( $eutils_uri . "esummary.fcgi?db=sra&id=$uid&retmode=xm" );

	if ($summary) {
		return $summary;
	}
	else {
		warn("Warning: no SRA summary found for UID $uid");
		return undef;
	}
}

1;
