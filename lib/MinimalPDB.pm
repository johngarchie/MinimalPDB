=head1 NAME

MinimalPDB - a minimal library for reading and printing PDB files

=head1 SYNOPSIS

  use MinimalPDB ':all';

  while ( <STDIN> ) {
      chomp;
      my @record = parse_pdb_record $_;
      print format_pdb_record @record;
  }

=head1 DESCRIPTION

MinimalPDB allows users to easily read and write minimal PDB files.  Minimal
PDB files are those that use only the following record types: EXPDTA, MODEL,
ATOM, and ENDMDL.  Other record types can be read and written, but this module
will not be useful for parsing them.

This module is designed to provide a lightweight, fast interface for parsing
PDB files.  If you would prefer a more comprehensive module, BioPerl is likely
a better option for you.

=head1 ABOUT

  Created by:	 John Archie <lt>http://www.jarchie.com/<gt>
  Created on:    2008-04-12

  SVN Information:
    $LastChangedBy::                                                    $
    $LastChangedDate::                                                  $
    $LastChangedRevision::                                              $
    $URL::                                                              $

=cut

package MinimalPDB;

use warnings;
use strict;

use 5.8.0;
our $VERSION = 0.04;

require Exporter;
our @ISA = qw/Exporter/;

our @EXPORT_OK = qw/RECORD_NAME ATOM_SERIAL ATOM_NAME ATOM_ALTLOC ATOM_RESNAME ATOM_CHAINID ATOM_RESSEQ ATOM_ICODE ATOM_X ATOM_Y ATOM_Z ATOM_OCCUPANCY ATOM_TEMPFACTOR ATOM_ELEMENT ATOM_CHARGE MODEL_SERIAL EXPDTA_CONTINUATION EXPDTA_TECHNIQUE OTHER_EVERYTHING %RECOGNIZED_RECORDS &format_pdb_record &parse_pdb_record &is_atom &res_id/;

our %EXPORT_TAGS = ( 'all' => \@EXPORT_OK );


=head1 CONSTANTS

A PDB record is represented as an array where each index corresponds to a field
in the PDB record.  In general any whitespace at the start or end of each
field gets stripped, except whitespace that may be necessary for proper
formatting (fields are marked with an asterick below).

=head2 EXPDTA

  Idx | Columns | Constant            | Definition
  ----+---------+---------------------+-----------
    0 |   1- 6  | RECORD_NAME         | "EXPDTA"
    1 |   9-10  | EXPDTA_CONTINUATION | Allows concatenation of multiple
      |         |                     | records.
    2 |  11-80  | EXPDTA_TECHNIQUE    | The experimental technique(s)
      |         |                     | with optional comment describing
      |         |                     | the sample or experiment.*

* Whitespace is not trimmed.

=cut

use constant RECORD_NAME => 0;

use constant {
    EXPDTA_CONTINUATION => 1,
    EXPDTA_TECHNIQUE    => 2,
};


=head2 MODEL

  Idx | Columns | Constant     | Definition
  ----+---------+--------------+---------------------
    0 |   1- 6  | RECORD_NAME  | "MODEL "
    1 |  11-14  | MODEL_SERIAL | Model serial number.

=cut

use constant MODEL_SERIAL => 1;


=head2 ATOM

  Idx | Columns | Constant        | Definition
  ----|---------+-----------------+-------------------------
    0 |   1- 6  | RECORD_NAME     | "ATOM  "
    1 |   7-11  | ATOM_SERIAL     | Atom serial number.
    2 |  13-16  | ATOM_NAME       | Atom name.
    3 |  17     | ATOM_ALTLOC     | Alternate location indicator.
    4 |  18-20  | ATOM_RESNAME    | Residue name.
    5 |  22     | ATOM_CHAINID    | Chain identifier.*
    6 |  23-26  | ATOM_RESSEQ     | Residue sequence number.
    7 |  27     | ATOM_ICODE      | Code for insertion of residues.*
    8 |  31-38  | ATOM_X          | Orthogonal coordinates for X in Ang.
    9 |  39-46  | ATOM_Y          | Orthogonal coordinates for Y in Ang.
   10 |  47-54  | ATOM_Z          | Orthogonal coordinates for Z in Ang.
   11 |  55-60  | ATOM_OCCUPANCY  | Occupancy.
   12 |  61-66  | ATOM_TEMPFACTOR | Temperature factor.
   13 |  77-78  | ATOM_ELEMENT    | Element symbol, right-justified.
   14 |  79-80  | ATOM_CHARGE     | Charge on the atom.

* Whitespace is not trimmed.

=cut

# the fields for ATOM records
use constant {
    ATOM_SERIAL     => 1,
    ATOM_NAME       => 2,
    ATOM_ALTLOC     => 3,
    ATOM_RESNAME    => 4,
    ATOM_CHAINID    => 5,
    ATOM_RESSEQ     => 6,
    ATOM_ICODE      => 7,
    ATOM_X          => 8,
    ATOM_Y          => 9,
    ATOM_Z          => 10,
    ATOM_OCCUPANCY  => 11,
    ATOM_TEMPFACTOR => 12,
    ATOM_ELEMENT    => 13,
    ATOM_CHARGE     => 14,
};


=head2 ENDMDL

  Idx | Columns | Constant    | Definition
  ----+---------+-------------+-----------
    0 |   1- 6  | RECORD_NAME | "ENDMDL"

=head2 ANY OTHER PDB RECORD

  Idx | Columns | Constant         | Definition
  ----+---------+------------------+-----------------------------
    0 |   1- 6  | RECORD_NAME      | The unidentified record name.
    1 |   7-80  | OTHER_EVERYTHING | Everything else on the line.*

* Whitespace is not trimmed.

=cut

use constant OTHER_EVERYTHING => 1;


=head2 RECOGNIZED RECORDS

While not, strictly speaking, a constant.  A hash is provided to identify
records that this module considers part of a minimal PDB file.

C<$RECOGNIZED_RECORDS{$record[RECORD_NAME]}> is true if @record represents an
EXPDTA, MODEL, ATOM, or ENDMDL record.  Otherwise the value does not
exist (i.e. is false).

You can change this hash at your own peril.  Ought you?  Probably not.

=cut

our %RECOGNIZED_RECORDS = map { $_ => 1 } qw(EXPDTA MODEL ATOM HETATM ENDMDL);


=head1 FUNCTIONS

=over 4

=item B<parse_pdb_record($line)>

splits line and returns an array representing each field in the line.

=cut

sub parse_pdb_record($) {
    my($line) = @_;
    my @record;

    # Anatomy of an ATOM record:
    # 
    #                       resSeq                                              charge
    #             name resName  iCode                             tempFactor        |
    # ATOM..#####.++++#++++#++++#...++++++++########++++++++######++++++..........##++
    #       serial    altLoc        x       y       z       occupancy             |
    #                      chainID                                             element
    # 
    # Strings of '+' and '#' indicate fields.
    # Strings of '.' indicates unused positions or spaces.
    if($line =~ /^(ATOM\ \ |HETATM)(.....).  # record, serial
       (....)(.)                             # name, altLoc
       (....)(.)(....)(.)...                 # resName, chainID, resSeq, iCode
       (........)(........)(........)        # x, y, z
       (?:(......)(?:(......)(?:..........   # occupancy, tempFactor
       (..)(?:(..))?)?)?)?/x                 # element, charge
      ) {
        $record[RECORD_NAME]     = trim($1);
        $record[ATOM_SERIAL]     = trim($2);
        $record[ATOM_NAME]       = trim($3);
        $record[ATOM_ALTLOC]     = trim($4);
        $record[ATOM_RESNAME]    = trim($5);
        $record[ATOM_CHAINID]    =      $6 ;
        $record[ATOM_RESSEQ]     = trim($7);
        $record[ATOM_ICODE]      =      $8 ;
        $record[ATOM_X]          = trim($9);
        $record[ATOM_Y]          = trim($10);
        $record[ATOM_Z]          = trim($11);
        $record[ATOM_OCCUPANCY]  = trim($12);
        $record[ATOM_TEMPFACTOR] = trim($13);
        $record[ATOM_ELEMENT]    = trim($14);
        $record[ATOM_CHARGE]     = trim($15);

	$record[ATOM_TEMPFACTOR] = 0.00 unless $record[ATOM_TEMPFACTOR];
    }

    # Anatomy of a MODEL record:
    # 
    # MODEL.....####..................................................................
    #           serial
    # 
    # The string of '#' indicates the field.
    # Strings of '.' indicate unused positions or spaces.
    elsif($line =~ /^(MODEL )....(....)/) {    # record, serial
        $record[RECORD_NAME]  = trim($1);
        $record[MODEL_SERIAL] = trim($2);
    }

    # Anatomy of an ENDMDL record:
    # 
    # ENDMDL..........................................................................
    # 
    # Strings of '.' indicate unused positions or spaces.
    elsif($line =~ /^(ENDMDL)/) {    # record
        $record[RECORD_NAME] = trim($1);
    }

    # Anatomy of a EXPDTA record:
    # 
    #           technique
    # EXPDTA..##++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++..........
    #         continuation
    # 
    # Strings of '+' and '#' indicate fields.
    # Strings of '.' indicate unused positions or spaces.
    elsif($line =~ /^(EXPDTA)..(..)(.*)/) {    # record, cont, techniq
        $record[RECORD_NAME]         = trim($1);
        $record[EXPDTA_CONTINUATION] = trim($2);
        $record[EXPDTA_TECHNIQUE]    = trim($3);
    }

    # ...and a catch all for everything we don't recognize
    elsif($line =~ /^(......)(.*)/) {    # record, everything else
        $record[RECORD_NAME]      = trim($1);
        $record[OTHER_EVERYTHING] = $2;
    }
    elsif($line =~ /^(.*)/) {  # and finally, records that are too short
        $record[RECORD_NAME]      = trim($1);
        $record[OTHER_EVERYTHING] = "";
    }

    @record = map defined $_ ? $_ : "", @record;

    return @record;
}


=item B<format_pdb_record(@fields)>

formats the record in @fields (as returned by &parse_pdb_record above) and
returns the formatted PDB record.

=cut

sub format_pdb_record(@) {
    my(@record) = @_;

    local $^A = "";    # reset the variable where formats are stored

    # in honor of formats and fortran, here are some obligatory gotos.
    # in typical perl perversion, the gotos actually help clarity b/c
    # formats can't be indented...
    if($record[RECORD_NAME] eq "ATOM" || $record[RECORD_NAME] eq "HETATM") {
        if(length $record[ATOM_NAME] == 3) {         # crazy special case for
            $record[ATOM_NAME] = " " . $record[ATOM_NAME];  # correct formatting
	}
        goto format_atom_record;
    } elsif($record[RECORD_NAME] eq "MODEL") {
        goto format_model_record;
    } elsif($record[RECORD_NAME] eq "ENDMDL") {
        goto format_endmdl_record;
    } elsif($record[RECORD_NAME] eq "EXPDTA") {
        goto format_expdta_record;
    } else {
        goto format_other_record;
    }


format_atom_record:
formline <<ATOM_END, @record;
@<<<<<@#### @|||@@<<<@@>>>@   @###.###@###.###@###.###@##.##@##.##          @>@<
ATOM_END
goto return_formatted_record;

format_model_record:
formline <<MODEL_END, @record;
@<<<<<    @>>>                                                                  
MODEL_END
goto return_formatted_record;

format_endmdl_record:
formline <<ENDMDL_END, @record;
@<<<<<                                                                          
ENDMDL_END
goto return_formatted_record;

format_expdta_record:
formline <<EXPDTA_END, @record;
@<<<<<  @>@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
EXPDTA_END
goto return_formatted_record;

format_other_record:
formline <<OTHER_END, @_;
@<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
OTHER_END
goto return_formatted_record;


    return_formatted_record:
    chomp $^A;
    return sprintf "%-80s\n", $^A;
}

=item B<is_atom(@record)>

returns true if @record represents an ATOM or HETATM record

=cut
sub is_atom(\@) {
    return $_[0]->[RECORD_NAME] eq "ATOM" ||
	   $_[0]->[RECORD_NAME] eq "HETATM";
}

=item B<res_id(@record)>

returns a string identifier for the residue the concatenation of the
ATOM_CHAINID, ATOM_RESSEQ, and ATOM_ICODE fields; assumes the input record is
an atom

=cut
sub res_id(\@) {
    return $_[0]->[ATOM_RESSEQ] . $_[0]->[ATOM_ICODE] . $_[0]->[ATOM_CHAINID];
}



############################################################################
## trim($string)
##   a private function that returns $string with any whitespace at the
##   beginning or end removed; returns undef if string is not defined
############################################################################
sub trim($) {
    my($string) = @_;

    if(defined $string) {
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
    }

    return $string;
}

=back

=head1 BUGS

&parse_pdb_record does not ensure the correctness of the input file.  The
behavior is reasonable (i.e., the right columns are returned to the user), but
no guarantee is provided that the column is a specific type.  For example
$record[ATOM_X] is not guaranteed to be a number--just the characters
in the PDB file where the x-coordinate of an ATOM record is stored.

=head1 SEE ALSO

http://www.wwpdb.org/documentation/format32/v3.2.html

=cut

1;
