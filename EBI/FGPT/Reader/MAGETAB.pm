#!/usr/bin/env perl
#
# EBI/FGPT/Reader/MAGETAB.pm
#
# Anna Farne 2012 ArrayExpress team, EBI
#
# $Id: MAGETAB.pm 25036 2014-01-16 13:51:08Z emma $
#

=pod

=head1 NAME

EBI::FGPT::Reader::MAGETAB - a module to parse and validate the contents of a MAGETAB document

=head1 SYNOPSIS

 use EBI::FGPT::Reader::MAGETAB;

 my $check_sets = {
	'EBI::FGPT::CheckSet::AEArchive' => 'ae_validation',
	'EBI::FGPT::CheckSet::Curation'  => 'curator_checks',
 };

 my $idf = $ARGV[0];
 my $checker = EBI::FGPT::Reader::MAGETAB->new( 
    'idf'                  => $idf, 
    'check_sets'           => $check_sets,
    'data_dir'             => $data_dir,
 );
 $checker->parse();

 $checker->print_checker_status();

=head1 DESCRIPTION

EBI::FGPT::Reader::MAGETAB attempts a simple parse of a MAGE-TAB IDF and any SDRFs and Data Matrix
files that it references.

An C<mtab_doc> can be provided instead of an C<idf>. This will be split into its [IDF] and [SDRF] sections
before parsing.

If the simple check is successful it proceeds to a full parse of the MAGE-TAB files
using the Bio::MAGETAB modules.

Additional checks can be called at the appropriate stage in parsing by passing a list of
EBI::FGPT::CheckSet class names to the Checker object.

Errors and warnings generated by all checks can be set to write to log files.

=head1 ATTRIBUTES

=over 2

=item idf (either idf or mtab_doc required)

The IDF file to be checked 

=item mtab_doc (either idf or mtab_doc required)

The combined magetab document to be checked

=item data_dir (default is current directory)

The directory where the data files and SDRF file can be found

=item check_sets (optional)

A hashref of L<EBI::FGPT::CheckSet> modules and names for the logs 
they will produce. The modules can provide extra checks to run in
addition to the main validation

=item accession (optional)

Provide an experiment accession number to avoid missing accession
number errors being produced by some CheckSets

=item report_writer (optional)

A Log::Log4perl::Appender with a EBI::FGPT::Writer::Report
dispatcher class to produce logs for curators

=item skip_data_checks (default is 0)

Set to 1 or 0 to indicate if data file checks should be skipped

=back

=head1 METHODS

=over 2

=item parse

Runs simple and then full MAGE-TAB parse on the specified IDF. Calls
additional checks provided by EBI::FGPT::CheckSets at the
appropriate points

=item split_mtab_doc
 
 my $checker = EBI::FGPT::Reader::MAGETAB->new( 
    'mtab_doc'             => $mtab_doc_path, 
 );
 
 $checker->split_mtab_doc( idf => $idf_path, sdrf => $sdrf_path ); 
 
Splits a combined magetab document into its [IDF] and [SDRF] components and
creates them with the name/path specified. Method returns the full path of the 
IDF created in scalar context, or full paths of the sdrf and idf in list context.

This method is used internally if C<parse()> is called and no idf attribute 
has been set.

=item has_errors(checker_name)

Returns TRUE if any errors have been logged by the logger with name checker_name

If no checker_name is specified it will return the error status of the EBI::FGPT::Reader::MAGETAB logger
and all CheckSet loggers (e.g. positive number if any of the loggers have found errors)

=item print_checker_status(checker_name)

Prints the number of warnings and errors accumulated by the logger with name checker_name

If no checker_name is specified it will print the status of the EBI::FGPT::Reader::MAGETAB logger
and all CheckSet loggers

=item reset_checker_status(checker_name)

Resets checker_name logger's error and warn counts to 0

If no checker_name is specified it will reset the counts for the EBI::FGPT::Reader::MAGETAB logger
and all CheckSet loggers

=item get_magetab

Get the Bio::MAGETAB object which is created after a full parse is complete

=item get_input_name

Get the name of the input file checked (either idf or mtab_doc) - for use in logging

=item get_data_file_path($file_object)

Get the file path of a Bio::MAGETAB::Data object in the parser's data_dir directory

=item logdie fatal error warn info debug

Use Log4perl logging options to report errors, e.g. $checker->error("Some error message")

=cut

package EBI::FGPT::Reader::MAGETAB;

use Data::Dumper;

use Moose;
use MooseX::FollowPBP;

use 5.008008;

use Carp;
use English qw( -no_match_vars );

use Log::Log4perl;
use Log::Dispatch::File;
use Log::Log4perl::Level;
Log::Log4perl::Logger::create_custom_level( "REPORT", "WARN" );

use File::Spec;
use Cwd;

use EBI::FGPT::Reader::MAGETAB::Builder;
use EBI::FGPT::Reader::MAGETAB::IDFSimple;
use EBI::FGPT::Reader::MAGETAB::SDRFSimple;
use EBI::FGPT::Reader::MAGETAB::DataMatrixSimple;

use Bio::MAGETAB::Util::Reader;
use Bio::MAGETAB::Util::Reader::IDF;
use Bio::MAGETAB::Util::Reader::SDRF;
use Bio::MAGETAB::Util::Reader::Tabfile;
use Bio::MAGETAB;

has 'idf'          => ( is => 'rw', isa => 'Str' );
has 'mtab_doc'     => ( is => 'rw', isa => 'Str' );
has 'input_name'   => ( is => 'rw', isa => 'Str', trigger => \&_set_report_input_name );
has 'parse_failed' => ( is => 'rw', isa => 'Bool', default => 0 );
has 'magetab'      => ( is => 'rw', isa => 'Bio::MAGETAB' );
has 'data_dir'     => ( is => 'rw', isa => 'Str', default => "." );
has 'check_sets' => (
					  is      => 'rw',
					  isa     => 'HashRef',
					  default => sub { {} },
					  trigger => \&_initialize_check_sets
);
has 'accession'        => ( is => 'rw', isa => 'Str' );
has 'matrices'         => ( is => 'rw', isa => 'ArrayRef[Bio::MAGETAB::DataMatrix]' );
has 'skip_data_checks' => ( is => 'rw', isa => 'Bool', default => 0 );

# check_sets is a hashref of CheckSet classes to (optional) log file prefix names

has 'check_set_objects' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

has 'logger' => (
				  is      => 'rw',
				  isa     => 'Log::Log4perl::Logger',
				  builder => '_create_main_logger',
				  lazy    => 1,
				  handles => [qw(logdie fatal error warn info debug report)],
);
has 'report_writer' => (
						 is       => 'rw',
						 isa      => 'Log::Log4perl::Appender',
						 required => 0,
						 trigger  => \&_set_report_input_name,
);

has 'atlas_report_writer' => (
							   is       => 'rw',
							   isa      => 'Log::Log4perl::Appender',
							   required => 0,
							   trigger  => \&_set_atlas_report_input_name,
);

has 'verbose_logging' => (
                            is      => 'rw',
                            isa     => 'Bool',
                            default => 0
                        );

# Set the input_name attribute to the IDF or magetab doc name
# unless it has been specified as something else in constructor
sub BUILDARGS
{
	my ( $class, $args ) = @_;

	# Set the input file name to use in creating log file names
	my $input =
	    $args->{input_name} ? $args->{input_name}
	  : $args->{idf}        ? $args->{idf}
	  : $args->{mtab_doc};

	$args->{input_name} = $input;
	return $args;
}

# Check we have something to read
sub BUILD
{

	my ($self) = @_;

	if ( $self->get_idf and $self->get_mtab_doc )
	{
		$self->logdie(
"MAGETAB reader created with both an IDF and combined MAGE-TAB document - this is not valid"
		);
	}

	unless ( $self->get_idf or $self->get_mtab_doc )
	{
		$self->logdie(
"MAGETAB reader created without an IDF or combined MAGE-TAB document - this is not valid"
		);
	}

}

# Tell report writer what the input file name is as the name will be used eventually as the report file's prefix
sub _set_report_input_name
{

	my ($self) = @_;

	if ( my $reporter = $self->get_report_writer )
	{
		$reporter->set_input_name( $self->get_input_name );
	}
}

# Report writer needs an "input name" to construct the report file's name. Here the "ATLAS" string has
# to be inserted somewhere between the dir path and the actual IDF/MAGE-TAB file name, not as a simple
# prefix or suffix. Putting the "ATLAS" string as a prefix of the MAGETAB Reader object's "input_name"
# will result in errors like this when the script is called with IDF/MAGE-TAB file in full path:

# Could not open log file ATLAS_/ebi/microarray/home/..../expt_E-MEXP-3091.idf_error.log for writing
# - No such file or directory

# Putting the string as a suffix will result it in being chopped off together with the .txt extension
# of the "input_name", and the "report_input_name" and "atlas_report_input_name" will no longer
# be distinguishable from each other.

sub _set_atlas_report_input_name
{

	my ($self) = @_;

	if ( my $reporter = $self->get_atlas_report_writer )
	{
		my $orig_input_name = $self->get_input_name;

		# for input IDF/MAGE-TAB files with full path:
		my ( $vol, $dir, $name ) = File::Spec->splitpath($orig_input_name);

		# Very often the input name doesn't include any dir information,
		# e.g. when the input IDF/MAGE-TAB file is in the current working
		# directory and nobody would specify it with its full path.
		# In that case splitpath wouldn't find any directory info, hence `pwd` call.
		# One catch is that pwd value doesn't come with the last slash like
		# splitpath does, so retrofit here or else dir name and file name will
		# be concatenated without a slash in between.

		if ( $dir eq '' )
		{
			$dir = `pwd`;
			chomp $dir;
			$dir = $dir . "/";
		}

		$reporter->set_input_name( $dir . "ATLAS_" . $name );
	}
}

sub _create_main_logger
{

	my ($self) = @_;

	my $logger = $self->create_logger( __PACKAGE__, "validate" );
	return $logger;
}

# load the check set modules, create instances and set up loggers
sub _initialize_check_sets
{

	my ( $self, $new_check_sets, $old_check_sets ) = @_;

	$self->debug("Initializing check sets");

	# Attempt to load the requested CheckSet modules before we start parsing anything
	# Convert module name to path so we can use it in 'require'
	foreach my $checkset_module ( keys %{ $new_check_sets || {} } )
	{
		my @dirs = split "::", $checkset_module;
		my $module_path = File::Spec->catfile(@dirs);
		$module_path .= ".pm";

		$self->debug("Attempting to load $checkset_module");

		eval { require $module_path; };
		if ($EVAL_ERROR)
		{
			$self->logdie("Could not load $checkset_module - $EVAL_ERROR");
		}
        
		# Create the check set object and its logger
		my $file_prefix = $new_check_sets->{$checkset_module};
		my $params = {
			   logger           => $self->create_logger( $checkset_module, $file_prefix ),
			   data_dir         => $self->get_data_dir,
			   input_name       => $self->get_input_name,
			   skip_data_checks => $self->get_skip_data_checks,
		};
		if ( $self->get_report_writer )
		{
			$params->{report_writer} = $self->get_report_writer;
		}

		if ( ( $self->get_atlas_report_writer ) && ( $dirs[-1] eq 'AEAtlas' ) )
		{
			$params->{report_writer} = $self->get_atlas_report_writer;
		}

		my $checkset = $checkset_module->new($params);

		# Store the check set object so we can use it during checking
		$self->get_check_set_objects->{$checkset_module} = $checkset;
	}
}

sub create_logger
{

	my ( $self, $logger_name, $file_prefix ) = @_;

	# Create logger layout
	my $layout = Log::Log4perl::Layout::PatternLayout->new("%c{1} %p - %m%n");

	# Create new logger
	my $logger = Log::Log4perl->get_logger($logger_name);
	$logger->additivity(0);
	$logger->level($DEBUG);

	# Create screen appender
	my $screen_appender = Log::Log4perl::Appender->new(
														"Log::Log4perl::Appender::Screen",
														name => $logger_name . "_screen",
														stderr => 0,
	);
	$screen_appender->layout($layout);
    $screen_appender->threshold($WARN);
	
    # Switch on verbose logging, if requested.
    if( $self->get_verbose_logging ) {
        $screen_appender->threshold($DEBUG);
    }

	$logger->add_appender($screen_appender);

	# Create appender to count errors and warnings for each level of checks
	my $checker_status = Log::Log4perl::Appender->new( "EBI::FGPT::Reader::Status",
													  name => $logger_name . "_status", );

	#$checker_status->additivity(0);
	$logger->add_appender($checker_status);

	# If file prefix provided create a file appender.
	if ($file_prefix)
	{
		my $filename;
		$filename = $self->get_idf or $filename = $self->get_mtab_doc;
		my ( $vol, $dir, $name ) = File::Spec->splitpath($filename);

		# Write log to the same directory as the input file
		my $path;
		if ($dir)
		{
			$path = File::Spec->catfile( $dir, $file_prefix . "_$name.log" );
		}
		else
		{
			$path = $file_prefix . "_$name.log";
		}

		my $file_appender = Log::Log4perl::Appender->new(
														  "Log::Dispatch::File",
														  filename => $path,
														  mode     => "write",
		);
		$file_appender->threshold($WARN);

		$logger->add_appender($file_appender);
	}

	# If we have a "* report writer" appender object, we log to that too,
	# in addition to any file appender object we may have created
	# using specific a file prefix (see code block above)

	# The "* report writer" appender objects are often set in the
	# wrapper module EBI/FGPT/Reader/MAGETABChecker.pm

	# ArrayExpress (FGPT code) and MAGE-TAB (CPAN code) checks have
	# report writer appender added to an ArrayExpress/MAGETAB logger.

	# The appender for AEAtlas checks is added to a different logger,
	# specific for the Atlas.

	if (    ( $logger_name eq 'EBI::FGPT::CheckSet::AEAtlas' )
		 && ( my $atlas_report = $self->get_atlas_report_writer ) )
	{
		$logger->add_appender($atlas_report);
	}

	elsif (    ( $logger_name ne 'EBI::FGPT::CheckSet::AEAtlas' )
			&& ( my $report = $self->get_report_writer ) )
	{
		$logger->add_appender($report);
	}

	return $logger;
}

sub error_section
{
	my ( $self, $name ) = @_;
	my $report = $self->get_report_writer or return;
	$report->error_section($name);
}

sub report_section
{
	my ( $self, $name ) = @_;
	my $report = $self->get_report_writer or return;
	$report->report_section($name);
}

# We need to be able to create publications in cases where
# no title is specified in IDF. To do this we have to override
# the IDF reader's create publication method to create default titles
sub _create_partial_publications
{

	my ($self) = @_;

	my $BLANK = qr/\A [ ]* \z/xms;

	my @publications;
	my $counter;
  PUBL:
	foreach my $p_data ( @{ $self->get_text_store()->{'publication'} } )
	{

		$counter++;

		unless ( defined $p_data->{'title'} && $p_data->{'title'} !~ $BLANK )
		{

			# If any other publication attributes are provided we add
			# a default publication title
			if ( grep { $_ } values %{$p_data} )
			{
				$p_data->{'title'} = "unknown $counter";
			}
		}

		my @wanted = grep { $_ !~ /^status|termSource|accession$/ } keys %{$p_data};
		my %args = map { $_ => $p_data->{$_} } @wanted;

		if ( defined $p_data->{'status'} )
		{

			my $termsource;
			if ( my $ts = $p_data->{'termSource'} )
			{
				$termsource = $self->get_builder()->get_term_source( { 'name' => $ts, } );
			}

			my $status = $self->get_builder()->find_or_create_controlled_term(
													 {
													   'category' => 'PublicationStatus',
													   'value'    => $p_data->{'status'},
													   'termSource' => $termsource,
													 }
			);

			if ( defined $p_data->{'accession'} && !defined $status->get_accession() )
			{
				$status->set_accession( $p_data->{'accession'} );
				$self->get_builder()->update($status);
			}

			$args{'status'} = $status;
		}

		my $publication = $self->get_builder()->find_or_create_publication( \%args );

		push @publications, $publication;
	}

	return \@publications;
}
no warnings 'redefine';
*Bio::MAGETAB::Util::Reader::IDF::_create_publications = \&_create_partial_publications;
use warnings 'redefine';

sub print_checker_status
{
	my ( $self, $checker_name ) = @_;

	my @to_do;

	if ($checker_name)
	{
		push @to_do, $checker_name;
	}
	else
	{
		push @to_do, __PACKAGE__, keys %{ $self->get_check_sets };
	}

	foreach my $checker_name (@to_do)
	{
		my $appender_name = $checker_name . "_status";

		my $checker_status = Log::Log4perl->appender_by_name($appender_name)
		  or die("Could not find log appender named \"$appender_name\"");

		print "Number of $checker_name warnings: "
		  . $checker_status->howmany("WARN") . "\n";
		print "Number of $checker_name errors: "
		  . $checker_status->howmany("ERROR") . "\n";
	}
}

sub has_errors
{

	my ( $self, $checker_name ) = @_;

	return $self->has_status( "has_errors", $checker_name );
}

sub has_warnings
{

	my ( $self, $checker_name ) = @_;

	return $self->has_status( "has_warnings", $checker_name );
}

sub has_status
{
	my ( $self, $has_method, $checker_name ) = @_;

	my @to_do;

	if ($checker_name)
	{
		push @to_do, $checker_name;
	}
	else
	{
		push @to_do, __PACKAGE__, keys %{ $self->get_check_sets };
	}

	my $total_errors = 0;

	foreach my $checker_name (@to_do)
	{
		my $appender_name = $checker_name . "_status";

		my $checker_status = Log::Log4perl->appender_by_name($appender_name)
		  or die("Could not find log appender named \"$appender_name\"");

		$total_errors += $checker_status->$has_method;
	}

	return $total_errors;
}

sub reset_checker_status
{
	my ( $self, $checker_name ) = @_;

	my @to_do;

	if ($checker_name)
	{
		push @to_do, $checker_name;
	}
	else
	{
		push @to_do, __PACKAGE__, keys %{ $self->get_check_sets };
	}

	foreach my $checker_name (@to_do)
	{
		my $appender_name = $checker_name . "_status";

		my $checker_status = Log::Log4perl->appender_by_name($appender_name)
		  or die("Could not find log appender named \"$appender_name\"");
		$checker_status->reset;
	}
}

sub split_mtab_doc
{
	my ( $self, %args ) = @_;

	$self->error_section("Splitting MAGE-TAB doc START");

	# Sanity checks
	unless ( $args{sdrf} and $args{idf} )
	{
		$self->logdie("split_mtab_doc called without sdrf and idf arguements");
	}

	my $mtab = $self->get_mtab_doc
	  or $self->logdie("Cannot split magetab doc - no mtab_doc set");

	$self->info("Splitting combined MAGE-TAB doc $mtab");

	my $splitter = Bio::MAGETAB::Util::Reader::Tabfile->new( 'uri' => $mtab, );

	# Needed for Text::CSV_XS parser that Bio::MAGETAB::Util::Reader::Tabfile uses
	local $/ = $splitter->get_eol_char();

	open( my $idf_fh, ">", $args{idf} )
	  or $self->logdie( "Could not open IDF ", $args{idf}, " for writing" );

	# Write sdrf to specified location
	open( my $sdrf_fh, ">", $args{sdrf} )
	  or $self->logdie( "Could not open SDRF ", $args{sdrf}, " for writing" );
	my ( $vol, $dir, $sdrf_name ) = File::Spec->splitpath( $args{sdrf} );

	my $sdrf_section;
	my $idf_found;
	while ( my $line = $splitter->getline )
	{
		$splitter->strip_whitespace($line);

		# FIXME: Ideally this should be in strip_whitespace
		# method of Bio::MAGETAB::Util::Reader::Tabfile

		# Remove extra/trailing whitespaces in square brackets,
		# e.g. "FactorValue[ Age]", "FactorValue[ Sex ]".

		$line =~ s/\[\s+/\[/g;
		$line =~ s/\s+\]/\]/g;

		if ( $line->[0] eq "[IDF]" .. $line->[0] eq "[SDRF]" )
		{

			$idf_found = 1;

			if ( $line->[0] eq "[SDRF]" )
			{

				# Replace this with the SDRF File name
				$line = [ "SDRF File", $sdrf_name ];

				# We are now starting the SDRF section
				$sdrf_section = 1;
			}

			# Put everything else, except [IDF] delimiter into new idf
			unless ( $line->[0] eq "[IDF]" )
			{
				print $idf_fh join "\t", @$line;
				print $idf_fh "\n";
			}
		}
		elsif ($sdrf_section)
		{

			# Put everything after the [SDRF] delimiter into new sdrf
			print $sdrf_fh join "\t", @$line;
			print $sdrf_fh "\n";
		}
	}

	close $idf_fh;
	close $sdrf_fh;

	my $idf_full  = File::Spec->rel2abs( $args{idf} );
	my $sdrf_full = File::Spec->rel2abs( $args{sdrf} );

	unless ($idf_found)
	{

		# Delete the temp files then die
		unlink $idf_full;
		unlink $sdrf_full;
		$self->logdie("Could not split $mtab into IDF and SDRF, no [IDF] section found");
	}

	return wantarray ? ( $idf_full, $sdrf_full ) : $idf_full;
}

after 'split_mtab_doc' => sub {
	my ($self) = @_;
	$self->error_section("Splitting MAGE-TAB doc END");
};

# track any temp files created so we can tidy up afterwards
my @delete_after_parse;

sub parse
{
	my ($self) = @_;

	my $idf = $self->get_idf;

	$self->error_section("Naive parsing START");

	# If we have a combined mtab_doc instead of an IDF we need to split it
	unless ($idf)
	{

		my $timestamp = time;

		my ( $vol, $dir, $file ) = File::Spec->splitpath( $self->get_mtab_doc );

		if ($dir)
		{
			$idf = File::Spec->catfile( $dir, "idf_$timestamp.tmp" );
		}
		else
		{
			$idf = "idf_$timestamp.tmp";
		}
		my $sdrf = File::Spec->catfile( $self->get_data_dir, "sdrf_$timestamp.tmp" );

		# Split the doc and store the names of the files created so we can
		# delete them later
		@delete_after_parse = $self->split_mtab_doc( idf => $idf, sdrf => $sdrf );

		$self->set_idf($idf);
	}

	my $logger  = $self->get_logger;
	my $builder = EBI::FGPT::Reader::MAGETAB::Builder->new();

	# Parse IDF using subclass of IDF parser which does some extra checks
	# croak overridden in parser subclass to get as much info back from IDF
	# as possible
	$self->error_section("Naive IDF parsing START");
	$logger->info( "Attempting to parse IDF ", $idf );

	# Parse IDF
	my $idf_parser = EBI::FGPT::Reader::MAGETAB::IDFSimple->new(
																 {
																   uri     => $idf,
																   builder => $builder,
																   logger  => $logger,
																 }
	);
	my $investigation;
	eval { $investigation = $idf_parser->parse(); };
	if ($EVAL_ERROR)
	{
		$logger->error( "IDF parsing failed: ", $EVAL_ERROR );
		return;

	# FIXME. what should we do if idf cannot be parsed? still try to find and check sdrfs?
	}

	# Set externally provided accession (often a dummy) as a
	# Comment of the investigation object. This accession is
	# not written back into the actual idf file
	$self->_add_accession($investigation);

	$idf_parser->validate_grouped_data();

	$self->report_section("Experiment Description");
	$self->report( $investigation->get_description );

	my @data_files;

	# Run additional checks on IDF
	foreach my $checkset ( values %{ $self->get_check_set_objects || {} } )
	{

		$checkset->set_investigation($investigation);

		$checkset->run_idf_checks;
		if ( $checkset->can('get_additional_files') )
		{
			@data_files = $checkset->get_additional_files;
		}
	}

	$self->error_section("Naive IDF parsing END");

	# Naively parse any SDRFs identified in IDF
	$self->error_section("Naive SDRF parsing START");
	$logger->info("Attempting naive parse of SDRFs");
	my @sdrfs = $investigation->get_sdrfs;

	my ( @assays, @scans, @norms );
	foreach my $sdrf (@sdrfs)
	{

		my $sdrf_name = $sdrf->get_uri;
		$sdrf_name =~ s/file://;

		$self->debug( "SDRF name: $sdrf_name, data dir: ", $self->get_data_dir );

		my $naive_reader = EBI::FGPT::Reader::MAGETAB::SDRFSimple->new(
						 {
						   investigation => $investigation,
						   logger        => $logger,
						   uri => File::Spec->catfile( $self->get_data_dir, $sdrf_name ),
						   checker => $self,
						   builder => $builder,
						 }
		);
		$naive_reader->parse_sdrf();
		push @data_files, @{ $naive_reader->get_file_info           || [] };
		push @assays,     keys %{ $naive_reader->get_hybridizations || {} };
		push @scans,      keys %{ $naive_reader->get_scans          || {} };
		push @norms,      keys %{ $naive_reader->get_normalizations || {} };

		my %arrays =
		  map { ( $_->{array} || "no array design" ) => 1 }
		  @{ $naive_reader->get_file_info || [] };
		$self->report_section("Array Designs");
		$self->report( join "\n", sort keys %arrays );

		# Pass simple SDRF readers to check sets for additional checking
		foreach my $checkset ( values %{ $self->get_check_set_objects || {} } )
		{
			$checkset->add_simple_sdrf($naive_reader);
		}
	}

	if (@sdrfs)
	{

		# Run additional simple SDRF checks
		foreach my $checkset ( values %{ $self->get_check_set_objects || {} } )
		{
			$checkset->run_simple_sdrf_checks();
		}
		$self->error_section("Naive SDRF parsing END");

		# Try to parse matrix files as problems will cause full parse to fail
		$self->error_section("Naive DataMatrix parsing START");
		$self->_parse_matrices( \@assays, \@scans, \@norms, @data_files );
		$self->error_section("Naive DataMatrix parsing END");

		$self->error_section("Naive parsing END");

		# Check for existence of data files then
		# exit if the naive parse has produced errors
		if ( $self->has_errors(__PACKAGE__) )
		{
			$logger->error("Naive parse shows that a full MAGE-TAB parse will fail");

            # If there's an AEAtlas CheckSet here, add fail code.
            if( $self->get_check_set_objects->{ "EBI::FGPT::CheckSet::AEAtlas" } ) {

                my $checkSets = $self->get_check_set_objects;

                $checkSets->{ "EBI::FGPT::CheckSet::AEAtlas" }->_add_atlas_fail_code( 999 );

                $checkSets->{ "EBI::FGPT::CheckSet::AEAtlas" }->error( "Atlas checks were not performed" );

                $self->set_check_set_objects( $checkSets );
            }

			$self->_check_files_exist(@data_files);
			return;
		}

		# Attempt full parse
		$self->error_section("Full MAGE-TAB parsing START");

		$builder = EBI::FGPT::Reader::MAGETAB::Builder->new();
		my $idf_path = File::Spec->rel2abs($idf);
		$logger->info( "Attempting full MAGE-TAB parse using IDF ", $idf_path );
		my $cwd = getcwd();

		# In order for the reader to find SDRF and data matrix in a different
		# directory from IDF we chdir to that location then refer to the IDF
		# by its full path
		chdir $self->get_data_dir
		  or $self->logdie( "Could not chdir to ", $self->get_data_dir, $! );

		# We do not parse the DataMatrix again as we have already done all
		# checks on it.
		my $reader = Bio::MAGETAB::Util::Reader->new(
													  {
														idf              => $idf_path,
														relaxed_parser   => 0,
														ignore_datafiles => 1,
														builder          => $builder,
														common_directory => 0,
													  }
		);

		my $magetab;
		eval { $magetab = $reader->parse(); };

		if ($EVAL_ERROR)
		{
			$logger->error( "Full parse failed with the following errors:\n",
							$EVAL_ERROR );
		}
		else
		{
			$logger->info("Full MAGE-TAB parse successful");

			$self->set_magetab($magetab);

			# Set externally provided accession
			# Assuming there is only 1 investigation in the magetab container
			$self->_add_accession( $magetab->get_investigations );

			# Run full SDRF checks
			$self->_check_assays_have_tech;
			foreach my $checkset ( values %{ $self->get_check_set_objects || {} } )
			{
				$checkset->set_magetab($magetab);
				$checkset->run_sdrf_checks();
			}
		}
		$self->error_section("Full MAGE-TAB parsing END");

		# Return to original working directory before checking
		# for existence of data files
		chdir $cwd
		  or $self->logdie( "Could not chdir to $cwd ", $! );

		# Check files exist
		$self->error_section("Checking files exist START");
		$self->_check_files_exist(@data_files);
		$self->error_section("Checking files exist END");
	}

	else
	{
		$logger->warn(
				  "No SDRFs identified in IDF - full MAGE-TAB parse cannot be completed");
	}
}

sub get_data_file_path
{

	my ( $self, $file ) = @_;

	unless ( $file->isa("Bio::MAGETAB::Data") )
	{
		$self->fatal(
"The argument passed to get_data_file_path must be a Bio::MAGETAB::Data object (got $file)"
		);
	}

	my $uri = $file->get_uri;
	$uri =~ s/^file://;

	my $path = File::Spec->catfile( $self->get_data_dir, $uri );
	return $path;
}

sub _add_accession
{
	my ( $self, $investigation ) = @_;

	my $acc = $self->get_accession;

	return unless ($acc);    # i.e. do not proceed if $acc is undef

	my $comment = Bio::MAGETAB::Comment->new(
											  {
												name  => 'ArrayExpressAccession',
												value => $acc,
											  }
	);

	my @comments = $investigation->get_comments;
	push @comments, $comment;
	$investigation->set_comments( \@comments );
}

sub _check_files_exist
{
	my ( $self, @data_files ) = @_;

	if ( $self->get_skip_data_checks )
	{
		$self->warn("Skipping check for presence of data files");
		return;
	}

	# Determine if it is seq submission from AEExperimentType
	my $is_seq;
	if ( $self->get_magetab )
	{
		my @comments = $self->get_magetab->get_comments;
		my @type_comments = grep { $_->get_name eq "AEExperimentType" } @comments;
		$is_seq = grep { $_->get_value =~ /seq/i } @type_comments;
	}

	$self->info("Checking for presence of data files");
	foreach my $file (@data_files)
	{
		my $path = File::Spec->catfile( $self->get_data_dir, $file->{name} );

		if ( $is_seq and $file->{type} eq "raw" )
		{
			$self->info(  "Skipping check for presence of raw data files for sequencing submission"
			);
			next;
		}

		unless ( -r $path )
		{
			$self->error("File $path not found or unreadable.\n");
			next;
		}

		if ( -s $path == 0 )
		{
			$self->error("File $path is empty (zero bytes).\n");
		}
	}
}

sub _parse_matrices
{
	my ( $self, $assays, $scans, $norms, @data_files ) = @_;

	if ( $self->get_skip_data_checks )
	{
		$self->warn("Skipping parse of data matrices");
		return;
	}

	my %sdrf_node_list_for = (
							   "Bio::MAGETAB::Assay"           => $assays,
							   "Bio::MAGETAB::DataAcquisition" => $scans,
							   "Bio::MAGETAB::Normalization"   => $norms,
	);

	my @matrices = grep { $_->{type} eq 'transformed' and $_->{name} } @data_files;
	my $builder = EBI::FGPT::Reader::MAGETAB::Builder->new(
														 {
														   relaxed_parser    => 1,
														   tech_type_default => "unknown"
														 }
	);

	# FIXME: this is time consuming. should just check the column headers
	# and throw error if reporter/comp identifiers are missing
	# no need to contruct all MatrixRows/DesignElements
	my @dms;
  MATRIX: foreach my $matrix (@matrices)
	{
		$self->info( "Attempting to parse DataMatrix ", $matrix->{name} );
		my $parser;
		my $dm;

		eval {
			$parser = EBI::FGPT::Reader::MAGETAB::DataMatrixSimple->new(
					{
					  uri => File::Spec->catfile( $self->get_data_dir, $matrix->{name} ),
					  builder => $builder,
					  logger  => $self->get_logger,
					}
			);
			$dm = $parser->parse();
		};

		if ($EVAL_ERROR)
		{
			$self->error( "Could not parse ", $matrix->{name}, ": $EVAL_ERROR" );
			next MATRIX;
		}

		push @dms, $dm;

		my %qts_for_node;

		foreach my $col ( @{ $dm->get_matrixColumns || [] } )
		{
			my $node_name_string = join ";",
			  map { $_->get_name } @{ $col->get_referencedNodes || [] };

			# Check for duplicate columns (e.g. QT repeated for a node)
			my $qt_name = $col->get_quantitationType->get_value;
			if ( $qts_for_node{$node_name_string}->{$qt_name} )
			{
				$self->error( "Duplicate column in matrix ",
							  $matrix->{name}, ": $node_name_string ($qt_name)" );
			}
			$qts_for_node{$node_name_string}->{$qt_name} = 1;

			# Check node exists in SDRF
			foreach my $node ( @{ $col->get_referencedNodes || [] } )
			{
				my $node_class = ref($node);
				$self->info( "Checking for existence of node ",
							 $node->get_name, " ($node_class)" );
				my $node_list = $sdrf_node_list_for{$node_class};
				if ( defined $node_list )
				{
					unless ( grep { $_ eq $node->get_name } @$node_list )
					{
						$self->error(
									  "Node ",
									  $node->get_name,
									  " not found in SDRF (matrix: ",
									  $matrix->{name},
									  ", column: ",
									  $col->get_columnNumber + 1,
									  ", node type: $node_class)"
						);
					}
				}
				else
				{
					$self->error("No node list found for $node_class");
				}

			}
		}

		my $previous_qts;
		my $previous_node;
		foreach my $node ( keys %qts_for_node )
		{
			my $qts = join ";", sort keys %{ $qts_for_node{$node} || {} };
			if ( $previous_qts and $previous_qts ne $qts )
			{
				$self->error( "Inconsistent QTs in matrix ",
						   $matrix->{name},
						   " e.g. $node has $qts, but $previous_node has $previous_qts" );
			}
			$previous_node = $node;
			$previous_qts  = $qts;
		}
	}

	# Store parsed matrices in case we want to do anything else with them
	$self->set_matrices( \@dms );
}

sub _check_assays_have_tech
{

	my ($self) = @_;

	# Bio::MAGETAB::Util::Reader::SDRF (from cpan release v1.21) creates
	# a dummy "unknown" technology type for assays when parsing but
	# "pre-deletes" it so we check for assays which did not have tech
	# type in the SDRF by seeing if the ControlledTerm linked to them
	# is available via the MAGETAB container or not
	my @terms = $self->get_magetab->get_controlledTerms;

	foreach my $assay ( $self->get_magetab->get_assays )
	{
		my $tech_type = $assay->get_technologyType;
		unless ( grep { $_ == $tech_type } @terms )
		{
			$self->error( "Assay ", $assay->get_name, " has no TechnologyType" );
		}
	}

}

# Tidy up any temporary files created
sub DEMOLISH
{
	foreach my $file (@delete_after_parse)
	{
		unlink $file;
	}
}

1;
