#!/usr/bin/env perl
#
# EBI/FGPT/Resource/pgDatabase/GXA.pm
#
# pgGXA.pm 2017-06-08 10:05:30 suhaib mohammed
# Copypasted and slightly adapted from GXA.pm

package EBI::FGPT::Resource::Database::pgGXA;

use strict;
use warnings;
use 5.10.0;

use Moose;
use MooseX::FollowPBP;

use Encode qw( encode );

use EBI::FGPT::Config qw($CONFIG);

extends 'EBI::FGPT::Resource::pgDatabase';

sub BUILD{

    my ($self) = @_;
    $self->set_dsn( $CONFIG->get_AE_PG_DSN() );
    $self->set_username ( $CONFIG->get_AE_PG_USERNAME() );
    $self->set_password ( $CONFIG->get_AE_PG_PASSWORD() );

}


sub fetch_experiment_titles_from_atlasdb {

    my ( $self, $accessions, $logger ) = @_;

    my $accessions4query = "'" . join( "', '", @{ $accessions } ) . "'";

    my $query = "
        select distinct ACCESSION, TITLE
        from EXPERIMENT
        where ACCESSION in ($accessions4query)
        and PRIVATE = 'false'
        order by ACCESSION";

    # Get the database handle.
    my $atlasDBH = $self->get_dbh
        or $logger->logdie( "Could not get database handle: $DBI::errstr" );

    $logger->info( "Querying Atlas database for experiment titles..." );

    # Prepare the query, returns statement handler.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    # Empty hash for the results.
    my $expAcc2title = {};

    # Go through the results and get the accessions and titles.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $expTitle ) = @{ $row };

        $expAcc2title->{ $expAcc } = $expTitle;
    }

    # Disconnect from the database.
    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2title;
}


sub fetch_human_degene_info_from_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        select distinct IDENTIFIER, EXPERIMENT, CONTRASTID, LOG2FOLD, PVAL, to_char( LAST_UPDATE, 'YYYY-MM-DD HH24:MI:SS' )
        from VW_DIFFANALYTICS
        inner join EXPERIMENT
        on EXPERIMENT = ACCESSION
        where PRIVATE = 'false'
        and ORGANISM = 'Homo sapiens'
        order by IDENTIFIER, EXPERIMENT, CONTRASTID";

    # Get the database handle.
    my $atlasDBH = $self->get_dbh
        or $logger->logdie( "Could not get database handle: $DBI::errstr" );

    $logger->info( "Querying Atlas database for differentially expressed human genes and corresponding statistics..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    # Empty hash to store results.
    my $geneID2expAcc2contrast2stats = {};

    # Go through the resulting rows.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        # Get the gene ID, experiment accession, contrast ID, log fold-change, p-value and last update date.
        my ( $identifier, $expAcc, $contrastID, $logFC, $pvalue ) = @{ $row };

        # Add the stats to the results hash.
        $geneID2expAcc2contrast2stats->{ $identifier }->{ $expAcc }->{ $contrastID }->{ "logfc" } = $logFC;
        $geneID2expAcc2contrast2stats->{ $identifier }->{ $expAcc }->{ $contrastID }->{ "pvalue" } = $pvalue;
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $geneID2expAcc2contrast2stats;
}


sub fetch_last_processing_dates_from_atlasdb {

    my ( $self, $accessions, $logger ) = @_;

    my $accessions4query = "'" . join( "', '", @{ $accessions } ) . "'";

    my $query = "
        select ACCESSION, to_char( LAST_UPDATE, 'YYYY-MM-DD HH24:MI:SS' )
        from EXPERIMENT
        where ACCESSION in ($accessions4query)
        and PRIVATE = 'false'";

    my $atlasDBH = $self->get_dbh
        or $logger->logdie( "Could not get database handle: $DBI::errstr" );

    $logger->info( "Querying Atlas database for last processing date of experiments..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $expAcc2date = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $procDate ) = @{ $row };

        # Add the dates to the hash.
        unless( $expAcc2date->{ $expAcc } ) {
            $expAcc2date->{ $expAcc } = $procDate;
        }
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2date;
}


sub fetch_pmids_from_atlasdb {

    my ( $self, $accessions, $logger ) = @_;

    my $accessions4query = "'" . join( "', '", @{ $accessions } ) . "'";

    my $query = "select ACCESSION, PUBMED_IDS from EXPERIMENT where ACCESSION in ($accessions4query)";

    my $atlasDBH = $self->get_dbh
        or $logger->logdie( "Could not get database handle: $DBI::errstr" );

    $logger->info( "Querying Atlas database for PubMed IDs..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $expAcc2pmids = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $pmidString ) =  @{ $row };

        my $pmids = [];

        if( $pmidString ) {
            my @splitString = split( ", ", $pmidString );

            push @{ $pmids }, @splitString;
        }

        $expAcc2pmids->{ $expAcc } = $pmids;
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2pmids;
}


sub fetch_degenes_experiments_contrasts_from_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        select distinct IDENTIFIER, EXPERIMENT, CONTRASTID
        from VW_DIFFANALYTICS
        inner join EXPERIMENT
        on EXPERIMENT = ACCESSION
        where PRIVATE = 'false'
        order by IDENTIFIER, EXPERIMENT, CONTRASTID";

    my $atlasDBH = $self->get_dbh;

    $logger->info( "Querying pg Atlas database for differentially expressed genes, experiments, and contrast IDs..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $geneIDs2expAccs2contrastIDs = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $geneID, $expAcc, $contrastID ) = @{ $row };

        unless( exists( $geneIDs2expAccs2contrastIDs->{ $geneID }->{ $expAcc } ) ) {

            $geneIDs2expAccs2contrastIDs->{ $geneID }->{ $expAcc } = [ $contrastID ];
        }
        else {
            push @{ $geneIDs2expAccs2contrastIDs->{ $geneID }->{ $expAcc } }, $contrastID;
        }
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $geneIDs2expAccs2contrastIDs;
}


sub fetch_baseline_genes_experiments_assaygroups_from_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        select distinct IDENTIFIER, EXPERIMENT, ASSAYGROUPID
        from RNASEQ_BSLN_EXPRESSIONS
        inner join EXPERIMENT
        on EXPERIMENT = ACCESSION
        where PRIVATE = 'false'
        and EXPRESSION > 0.5
        order by IDENTIFIER, EXPERIMENT, ASSAYGROUPID";

    my $atlasDBH = $self->get_dbh;

    $logger->info( "Querying pg Atlas database for baseline genes, experiments, and assay group IDs..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $geneIDs2expAccs2assayGroupIDs = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $geneID, $expAcc, $assayGroupID ) = @{ $row };

        unless( exists( $geneIDs2expAccs2assayGroupIDs->{ $geneID }->{ $expAcc } ) ) {

            $geneIDs2expAccs2assayGroupIDs->{ $geneID }->{ $expAcc } = [ $assayGroupID ];
        }
        else {
            push @{ $geneIDs2expAccs2assayGroupIDs->{ $geneID }->{ $expAcc } }, $assayGroupID;
        }
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $geneIDs2expAccs2assayGroupIDs;
}


sub fetch_differential_experiment_info_from_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        select accession, last_update from experiment
        where private = 'false'
        and type like '%DIFFERENTIAL'";

    my $atlasDBH = $self->get_dbh;

    $logger->info( "Querying pg Atlas database for differential experiment info..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $differentialExperimentsInfo = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $date, $title ) = @{ $row };

        $title = encode( 'UTF-8', $title );

        $differentialExperimentsInfo->{ $expAcc }->{ "date" } = $date;
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $differentialExperimentsInfo;
}


sub fetch_baseline_experiment_info_from_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        select accession, last_update from experiment
        where private = 'false'
        and type like '%BASELINE'";

    my $atlasDBH = $self->get_dbh;

    $logger->info( "Querying pg Atlas database for baseline experiment info..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $baselineExperimentsInfo = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $expAcc, $date, $title ) = @{ $row };

        $title = encode( 'UTF-8', $title );

        $baselineExperimentsInfo->{ $expAcc }->{ "date" } = $date;
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $baselineExperimentsInfo;
}

sub fetch_isl_processing_experiments {

    my ( $self ) = @_;

    # Query for all RNA-seq related rows.
    my $query = "
        select * from atlas_jobs
        where jobtype in ( 'isl_public', 'isl_private', 'isl_complete', 'isl_queue', 'baseline/rna-seq', 'differential/rna-seq' )";

    my $atlasDBH = $self->get_dbh;

    my $atlasSH = $atlasDBH->prepare( $query )
        or die( "ERROR: Could not prepare query: ", $atlasDBH->errstr );

    $atlasSH->execute or die( "ERROR: Could not execute query: ", $atlasSH->errstr );

    # Collect all the results by accession into a hash, so that we can
    # eliminate the ones that have already been submitted for Atlas processing.
    my $results = {};

    while( my $row = $atlasSH->fetchrow_arrayref ) {

        my ( $date, $jobtype, $acc ) = @{ $row };

        $results->{ $acc }->{ $jobtype } = 1;
    }

    $atlasSH->finish;

    # The accessions we want to collect will go in this array.
    my $expAccs = [];

    # Make sure these are not already submitted for Atlas processing.
    foreach my $acc ( keys %{ $results } ) {

        # If there's more than one entry for this accession, the experiment is
        # assumed to have been submitted for Atlas processing. Otherwise, the
        # only row in the table is the ISL row.
        if( scalar( keys %{ $results->{ $acc } } ) == 1 ) {

            push @{ $expAccs }, $acc;
        }
    }

    return $expAccs;
}


1;
