package TGI::Mutpro::Preprocess::Prior;
#
#----------------------------------
# $Authors: Beifang Niu and Adam D Scott
# $Date: 2014-01-14 14:34:50 -0500 (Tue Jan 14 14:34:50 CST 2014) $
# $Revision: 2 $
# $URL: $
# $Doc: $ do prioritization 
#----------------------------------
#
use strict;
use warnings;

use Carp;
use Getopt::Long;
use IO::File;
use FileHandle;

sub new {
    my $class = shift;
    my $this = {};
    $this->{_OUTPUT_DIR} = undef;
    $this->{_PVALUE_CUTOFF} = 0.05;
    $this->{_3D_CUTOFF} = 20;
    $this->{_1D_CUTOFF} = 0;
    $this->{_STAT} = undef;
    bless $this, $class;
    $this->process();
    return $this;
}

sub process {
    my $this = shift;
	$this->setOptions();
    #### processing ####
    # do prioritization 
	my ( $fhunipro , $proximityDir , $cosmicDir , $prioritizationDir ) = $this->getInputs();
    while ( my $line = <$fhunipro> ) {
        chomp $line;
        my ( undef, $uniprotId, ) = split /\t/, $line;
        # Only use Uniprot IDs with PDB structures
        next if ( $uniprotId !~ /\w+/ );
        # proximity file
        my $cosmicFile = "$cosmicDir\/$uniprotId\.ProximityFile\.csv";
        next unless( -e $cosmicFile );
        my $outputFile = "$prioritizationDir\/$uniprotId\.ProximityFile\.csv";
        print STDOUT $uniprotId."\n";
        # add annotation infor
        $this->doPrior( $cosmicFile , $outputFile , $uniprotId );
        #delete file if null
    }
    $fhunipro->close();
}

sub setOptions {
	my ( $this ) = @_;
    my ( $help, $options );
    unless( @ARGV ) { die $this->help_text(); }
    $options = GetOptions (
        'output-dir=s' => \$this->{_OUTPUT_DIR},
        'p-value-cutoff=f' => \$this->{_PVALUE_CUTOFF},
        '3d-distance-cutoff=i' => \$this->{_3D_CUTOFF},
        'linear-cutoff=i' => \$this->{_1D_CUTOFF},
        'help' => \$help,
    );
    if ( $help ) { print STDERR help_text(); exit 0; }
    unless( $options ) { die $this->help_text(); }
    unless( $this->{_OUTPUT_DIR} ) { warn 'You must provide output directory ! ', "\n"; die help_text(); }
    unless( -d $this->{_OUTPUT_DIR} ) { warn 'You must provide a valid output directory ! ', "\n"; die help_text(); }
	return;
}

sub getInputs {
	my ( $this ) = @_;
    my ( $UniprotIdFile, $proximityDir, $cosmicDir, $prioritizationDir, );
    $UniprotIdFile = "$this->{_OUTPUT_DIR}\/hugo.uniprot.pdb.transcript.csv";
    $proximityDir = "$this->{_OUTPUT_DIR}\/proximityFiles";
    $cosmicDir = "$proximityDir\/cosmicanno";
    $prioritizationDir = "$this->{_OUTPUT_DIR}\/prioritization";
    unless( -d $cosmicDir ) { warn "You must provide a valid COSMIC annotations directory ! \n"; die help_text(); }
    unless( -e $prioritizationDir ) { mkdir($prioritizationDir) || die "can not make prioritization result files directory\n"; }
    my $fhunipro = new FileHandle;
    unless( $fhunipro->open("<$UniprotIdFile") ) { die "Could not open Uniprot ID file !\n" };
	return ( $fhunipro , $proximityDir , $cosmicDir , $prioritizationDir );
}

# prioritization based on 
# COSMIC annotation results
sub doPrior {
    my ( $this , $proximityFile , $outputFile , $uniprotId ) = @_;
	my $outputContent = $this->getProximityInformation( $proximityFile );
	$this->writeOutput( $outputFile , $outputContent );
	return;
}

sub getProximityInformation {
	my ( $this , $proximityFile ) = @_;
    print STDOUT "-------$proximityFile---\n";
    # read COSMIC annotation information
    my $fhproximity = new FileHandle;
    unless( $fhproximity->open("<$proximityFile") ) { die "Could not open COSMIC annotated proximity file !\n" };
    # hash for filtering same pairs
    # but keep distances and P_vales
	my $pValueCutoff = $this->{_PVALUE_CUTOFF};
	my $spatialCutoff = $this->{_3D_CUTOFF};
	my $linearCutoff = $this->{_1D_CUTOFF};
    my %outputContent;
    while ( my $line = <$fhproximity> ) {
        if ($line =~ /^WARNING:/) {
			warn "HotSpot3D::Prior::doPrior warning: no chains were found for a structure in ".$proximityFile."\n";
			next;
		}
        next if ($line =~ /UniProt_ID1/);
        chomp($line);
        my @fields = split /\t/, $line;
        my ( $annoOneEnd, $annoTwoEnd, $uniprotCoorOneEnd, $uniprotCoorTwoEnd, );
        $annoOneEnd = $annoTwoEnd = "N\/A";
		if ( scalar @fields < 11 ) {
			warn "HotSpot3D::Prior::doPrior warning: bad line in ".$proximityFile.": ".$line."\n";
		}
        next if ( ($fields[2] =~ /N\/A/) or 
                  ($fields[3] =~ /N\/A/) or 
                  ($fields[9] =~ /N\/A/) or
				  ($fields[10] =~ /N\/A/));
        next unless ( ($fields[2] =~ /\d+/) and
                      ($fields[3] =~ /\d+/) and
                      ($fields[9] =~ /\d+/) and
					  ($fields[10] =~ /\d+/) );
        my $oneEndContent = join("\t", @fields[0..6]);
        my $twoEndContent = join("\t", @fields[7..13]);
        my $proInfo       = join(" ", @fields[14..16]);
        $uniprotCoorOneEnd = $fields[2] + $fields[3];
        $uniprotCoorTwoEnd = $fields[9] + $fields[10];
        my $linearDistance = abs($uniprotCoorOneEnd - $uniprotCoorTwoEnd);
        next if ( ( $fields[0] eq $fields[7] ) and
				  ( $linearDistance <= $linearCutoff) );
        next if ( $fields[16] > $pValueCutoff );
        next if ( $fields[14] > $spatialCutoff );
        # load infor into %outputContent hash
        if ( ( defined $outputContent{$oneEndContent}{$twoEndContent} ) or
			 ( defined $outputContent{$twoEndContent}{$oneEndContent} ) ) {
            if (defined $outputContent{$oneEndContent}{$twoEndContent}) {
                $outputContent{$oneEndContent}{$twoEndContent}{$proInfo} = 1;
            } else {
				$outputContent{$twoEndContent}{$oneEndContent}{$proInfo} = 1;
			}
        } else {
			$outputContent{$oneEndContent}{$twoEndContent}{$proInfo} = 1;
		}
    }
    $fhproximity->close();
	return \%outputContent;
}

sub writeOutput {
	my ( $this , $outputFile , $outputContent ) = @_;
    my $fhout = new FileHandle;
    unless( $fhout->open(">$outputFile") ) { die "Could not open prioritization output file to write !\n" };
	print STDOUT "Creating ".$outputFile."\n";
    # write prioritization result into file 
	$fhout->print( "UniProt_ID1\tChain1\tPosition1\tOffset1\tResidue_Name1\t" );
	$fhout->print( "Feature_Description1\tCOSMIC_Info1\t" );
	$fhout->print( "UniProt_ID2\tChain2\tPosition2\tOffset2\tResidue_Name2\t" );
	$fhout->print( "Feature_Description2\tCOSMIC_Info2\t" );
	$fhout->print( "Distance\tPDB_ID\tP_Value\n" );
    foreach my $mutation1 (keys %{$outputContent} ) {
        foreach my $mutation2 (keys %{$outputContent->{$mutation1}}) {
            print $fhout $mutation1."\t".$mutation2."\t";
            foreach my $content (keys %{$outputContent->{$mutation1}->{$mutation2}}) {
				print $fhout $content."|";
			}
            print $fhout "\n";
        }
    }
    $fhout->close();
	return;
}

sub help_text{
    my $this = shift;
        return <<HELP

Usage: hotspot3d prior [options]

                             REQUIRED
--output-dir                 Output directory

                             OPTIONAL
--p-value-cutoff             p_value cutoff(<=), default is 0.05
--3d-distance-cutoff         3D distance cutoff (<= Angstroms), default is 20
--linear-cutoff              Linear distance cutoff (> peptides), default is 0

--help                       this message

HELP

}

1;

