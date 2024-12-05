#!/usr/bin/env perl
#
=pod

=head1 NAME

Atlas::AtlasConfig::FactorsConfig - store information from an Atlas factors XML file and write it out.

=head1 SYNOPSIS

use Atlas::AtlasConfig::Reader qw( parseAtlasFactors );

my $factorsFile = "E-MTAB-3819-factors.xml";

my $factorsConfig = parseAtlasFactors( $factorsFile );

=head1 DESCRIPTION

This package represents information from Atlas -factors.xml files, and writes
it out in XML format.

=cut

package Atlas::AtlasConfig::FactorsConfig;

use strict;
use warnings;
use 5.10.0;

use Moose;
use MooseX::FollowPBP;
use Log::Log4perl;
use XML::Writer;
use IO::File;
use Atlas::Common qw( create_atlas_site_config );
use Atlas::Util qw( get_supporting_file);
use File::Spec;

has 'default_query_factor_type' => (
    is => 'rw',
    isa => 'Str',
    required => 1
);

has 'landing_page_display_name' => (
    is => 'rw',
    isa => 'Str', 
    required => 1
);

has 'default_filter_factors' => (
    is => 'rw',
    isa => 'ArrayRef[ HashRef ]',
    predicate => 'has_default_filter_factors'
);

has 'menu_filter_factor_types' => (
    is => 'rw',
    isa => 'ArrayRef',
    predicate => 'has_menu_filter_factor_types'
);

has 'species_mapping' => (
    is => 'rw',
    isa => 'ArrayRef[ HashRef ]',
    predicate => 'has_species_mapping'
);

has 'data_provider_url' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_data_provider_url'
);

has 'data_provider_description' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_data_provider_description'
);

has 'data_usage_agreement' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_data_usage_agreement'
);

has 'curated_sequence' => (
    is  => 'rw',
    isa => 'Bool',
    predicate => 'has_curated_sequence'
);


my $logger = Log::Log4perl->get_logger;

sub write_xml {

    my ( $self, $filename ) = @_;

    $logger->info( "Writing factors config to $filename ..." );
    
    my $gxaLicense = _read_gxa_license();

    unless( $gxaLicense ) {
        $logger->warn(
            "Did not get the GXA licence text for the XML file header."
        );
    }

    my $outputFile = IO::File->new( ">$filename" );

    my $xmlWriter = XML::Writer->new( 
        OUTPUT      => $outputFile,
        DATA_MODE   => 1,
        DATA_INDENT => 4
    );

    # XML declaration.
    $xmlWriter->xmlDecl( "ISO-8859-1" );
    
    # Add licence, if we got it.
    if( $gxaLicense ) {
        $xmlWriter->comment( $gxaLicense );
    }
    
    # Begin XML.
    $xmlWriter->startTag( "factors-definition" );
    
    # Add default filter factors (if any).
    if( $self->has_default_filter_factors ) {
        
        $xmlWriter->startTag( "defaultFilterFactors" );

        my $defaultFilterFactors = $self->get_default_filter_factors;

        foreach my $filterFactor ( @{ $defaultFilterFactors } ) {

            $xmlWriter->startTag( "filterFactor" );

            $xmlWriter->dataElement( "type" => $filterFactor->{ "type" } );

            $xmlWriter->dataElement( "value" => $filterFactor->{ "value" } );

            $xmlWriter->endTag( "filterFactor" );
        }

        $xmlWriter->endTag( "defaultFilterFactors" );
    }
    # Add an empty tag if not.
    else {
        $xmlWriter->emptyTag( "defaultFilterFactors" );
    }

    # Add the default query factor type.
    $xmlWriter->dataElement( "defaultQueryFactorType" => $self->get_default_query_factor_type );

    # Add the menu filter factor types, if any.
    if( $self->has_menu_filter_factor_types ) {

        my $menuFilterFactorTypes = join ", ", @{ $self->get_menu_filter_factor_types };

        $xmlWriter->dataElement( "menuFilterFactorTypes" => $menuFilterFactorTypes );
    }
    # Add an empty tag if not.
    else {
        $xmlWriter->emptyTag( "menuFilterFactorTypes" );
    }

    # Add the landing page display name.
    $xmlWriter->dataElement( "landingPageDisplayName" => $self->get_landing_page_display_name );

    # Add species mappings, if any.
    if( $self->has_species_mapping ) {

        $xmlWriter->startTag( "speciesMapping" );

        my $speciesMappings = $self->get_species_mapping;

        foreach my $mapping ( @{ $speciesMappings } ) {

            $xmlWriter->startTag( "mapping" );

            $xmlWriter->dataElement( "samples" => $mapping->{ "samples" } );

            $xmlWriter->dataElement( "genes" => $mapping->{ "genes" } );

            $xmlWriter->endTag( "mapping" );
        }
        
        $xmlWriter->endTag( "speciesMapping" );
    }
    # Add an empty tag if not.
    else {
        $xmlWriter->emptyTag( "speciesMapping" );
    }
    
    # Add the curated order flag, if any.
    if( $self->has_curated_sequence ) {
        $xmlWriter->dataElement( "orderFactor" => "curated" );
    }

    # Add the data provider info, if any.
    if( $self->has_data_provider_url ) {
        $xmlWriter->dataElement( "dataProviderURL" => $self->get_data_provider_url );
    }
    if( $self->has_data_provider_description ) {
        $xmlWriter->dataElement( "dataProviderDescription" => $self->get_data_provider_description );
    }

    # Add the Fort Lauderdale agreement flag, if any.
    if( $self->has_data_usage_agreement ) {

        my $atlasSiteConfig = create_atlas_site_config;

        my %allowedAgreements = map { $_ => 1 } @{ $atlasSiteConfig->get_allowed_data_usage_agreements };
        
        my $dataUsageAgreement = $self->get_data_usage_agreement;

        unless( $allowedAgreements{ $dataUsageAgreement } ) {

            $logger->logdie(
                "Unrecognised data usage agreement: ",
                $dataUsageAgreement,
                " -- please add this to the Atlas site config if you want to use it."
            );
        }
        
        $xmlWriter->dataElement( "disclaimer" => $dataUsageAgreement );
    }
    
    $xmlWriter->endTag( "factors-definition" );

    $xmlWriter->end;

    $outputFile->close;
}


sub _read_gxa_license {
    
    $logger->debug( "Reading GXA license..." );

    my $gxaLicenseFile = get_supporting_file("gxa_license.txt");
    
    unless( $gxaLicenseFile ) {
        $logger->logdie(
            "gxa_license_file is not defined in site config. Cannot continue."
        );
    }

    unless ( -r $gxaLicenseFile ) {
        # only read in the previous way merging $atlasProdDir if $gxaLicenseFile doesn't get a complete file
        my $atlasProdDir = $ENV{ "ATLAS_PROD" };
        unless( $atlasProdDir ) {
            $logger->logdie( 
                "ATLAS_PROD environment variable is not set. Cannot locate GXA license file."
            );
        }
        $gxaLicenseFile = File::Spec->catfile( $atlasProdDir, $gxaLicenseFile );
    }
    
    unless( -r $gxaLicenseFile ) {
        $logger->logdie(
            "Cannot read ",
            $gxaLicenseFile,
            " -- please ensure it exists and is readable."
        );
    }

    # Open the GXA license file.
    open( my $fh, "<", $gxaLicenseFile ) 
        or $logger->logdie( "Cannot open $gxaLicenseFile for reading: $!" );

    # Slurp file all in one go.
    my $gxaLicense = do { local $/; <$fh> };

    $logger->debug( "Successfully read GXA license." );

    return $gxaLicense;
}


1;
