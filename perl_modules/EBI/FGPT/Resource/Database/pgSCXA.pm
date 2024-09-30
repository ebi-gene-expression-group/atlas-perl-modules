#!/usr/bin/env perl
#
# EBI/FGPT/Resource/pgDatabase/pgSCXA.pm
#
# pgSCXA.pm suhaib mohammed
# Adapted and modified from pgGXA.pm

package EBI::FGPT::Resource::Database::pgSCXA;

use strict;
use warnings;
use 5.10.0;

use Moose;
use MooseX::FollowPBP;

use Encode qw( encode );

extends 'EBI::FGPT::Resource::pgDatabase';

sub BUILD{

    my ($self) = @_;
    $self->set_dsn( $ENV{'SC_PG_DSN'} );
    $self->set_username ( $ENV{'SC_PG_USERNAME'} );
    $self->set_password ( $ENV{'SC_PG_PASSWORD'} );

}


sub fetch_experiment_celltypes_from_sc_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        SELECT distinct EXPERIMENT_ACCESSION, VALUE FROM SCXA_CELL_GROUP
        WHERE VARIABLE like '%cell%' and VALUE !='Not available'";

    # Get the database handle.
    my $atlasDBH = $self->get_dbh
        or $logger->logdie( "Could not get database handle: $DBI::errstr" );

    $logger->info( "Querying SC Atlas database for experiment cell types..." );

    # Prepare the query, returns statement handler.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    # Empty hash for the results.
    my $expAcc2celltypes = {};
    my $expAcc;
    my $celltypes;

    # Go through the results and get the accessions and values.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        ($expAcc, $celltypes) = @{ $row }; 

        unless( exists( $expAcc2celltypes->{ $expAcc } ) ) {

                $expAcc2celltypes->{ $expAcc } = [ $celltypes ];
        }
        else {
            push @{ $expAcc2celltypes->{ $expAcc } }, $celltypes;
        } 
              
    }
    
    # Disconnect from the database.
    $atlasSH->finish;
    $logger->info( "Query successful." );

    return $expAcc2celltypes;
}


sub fetch_experiments_collections_from_sc_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        SELECT distinct EXP_ACC, COLL_ID FROM EXPERIMENT2COLLECTION 
        order by EXP_ACC, COLL_ID";

    my $atlasDBH = $self->get_dbh;

    $logger->info( "Querying SC Atlas database for experiment collections..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $expAcc2collections = {};
    my $expAcc;
    my $collection;

    # Go through the results and get the accessions and values.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        ($expAcc, $collection) = @{ $row };

        unless( exists( $expAcc2collections->{ $expAcc } ) ) {

                $expAcc2collections->{ $expAcc } = [ $collection ];
        }
        else {
            push @{ $expAcc2collections->{ $expAcc } }, $collection;
        }

    }


    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $expAcc2collections;
}


sub fetch_experiment_genes_from_sc_atlasdb {

    my ( $self, $logger ) = @_;

    my $query = "
        SELECT scgmg.gene_id, scg.experiment_accession, e.species, e.pubmed_ids from scxa_cell_group_marker_genes scgmg, scxa_cell_group scg, experiment e WHERE scg.experiment_accession = e.accession
        AND scgmg.cell_group_id = scg.id AND scgmg.marker_probability <="."'$ENV{'MARKER_GENE_PVAL'}'" ."AND e.private = 'FALSE'";

    my $atlasDBH = $self->get_dbh;

    $logger->info( "Querying SC Atlas database for gene information..." );

    # Get statement handle by preparing query.
    my $atlasSH = $atlasDBH->prepare( $query )
        or $logger->logdie( "Could not prepare query: ", $atlasDBH->errstr );

    # Execute the query.
    $atlasSH->execute or $logger->logdie( "Could not execute query: ", $atlasSH->errstr );

    my $geneIDs2expAccs2species2pubmed_ids = {};

    # Go through the resulting rows.
    while( my $row = $atlasSH->fetchrow_arrayref ) {

        # Get the gene ID, experiment accession, contrast ID, log fold-change, p-value and last update date.
        my ( $geneID, $expAcc, $species, $pubmed_ids ) = @{ $row };

        # Add species and pubmed_id to the results hash.
        $geneIDs2expAccs2species2pubmed_ids->{ $geneID }->{ $expAcc }->{ "species" } = $species;
        $geneIDs2expAccs2species2pubmed_ids->{ $geneID }->{ $expAcc }->{ "pubmed_id" } = $pubmed_ids;
    }

    $atlasSH->finish;

    $logger->info( "Query successful." );

    return $geneIDs2expAccs2species2pubmed_ids;
}

1;

