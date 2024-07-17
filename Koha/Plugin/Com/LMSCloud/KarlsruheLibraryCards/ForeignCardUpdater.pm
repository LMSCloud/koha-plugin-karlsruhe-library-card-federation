package Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::ForeignCardUpdater;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;
use utf8;

use C4::Context;
use Koha::Patrons;
use Koha::Patron::Debarments qw( AddDebarment DelDebarment );
use Koha::DateUtils qw( dt_from_string );

use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards;
use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardCentralServiceConnector;

sub new {
    my ( $class ) = @_;
    
    my $self = {};
    bless $self, $class;
    
    my $plugin = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards->new();
    my $checkPrefixes = $plugin->retrieve_data('kalib_prefixes') || '';
    my $debarmentType = $plugin->retrieve_data('set_debarment_type') || '';
    my $debarmentComment = $plugin->retrieve_data('set_debarment_comment');
    
    my @checkPrefixList = map  {   
                                    s/^\s+//;  # strip leading spaces
                                    s/\s+$//;  # strip trailing spaces
                                    $_         # return the modified string
                                 }
                                 split(/\|/,$checkPrefixes);
                                 
    $self->{prefixes} = \@checkPrefixList;
    $self->{debarmentType} = $debarmentType;
    $self->{debarmentComment} = $debarmentComment;
    
    return $self;
}

sub updateForeignCardStatus {
    my $self = shift;
    
    if (! scalar(@{$self->{prefixes}}) ) {
        print "No foreign card prefixes defined for the plugin\n";
        exit 0;
    }
    if (! $self->{debarmentType} ) {
        print "No debarment type for foreign cards defined if the status is locked.\n";
        exit 0;
    }
    
    my @cards = $self->getForeignCards();
    my $service = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardCentralServiceConnector->new();
    
    foreach my $cardNumber(@cards) {
        my $response = $service->getCardStatus($cardNumber);
        if ( $response->{is_success} ) {
            my $cardStatus = $response->{card_status};
            my $result = $self->updateCardStatus($cardNumber,$cardStatus);
            print "$cardNumber => $result\n";
        }
        else {
            print "$cardNumber => Error retrieving card stateusing central service: ", $response->{error_message}, "\n";
        }
    }
}

sub updateCardStatus {
    my $self = shift;
    my $cardNumber = shift;
    my $cardStatus = shift;
    
    my $debarmentType = $self->{debarmentType};
    my $debarmentComment = $self->{debarmentComment};
    
    my $patron = Koha::Patrons->find( { cardnumber => $cardNumber } );
    my $result = 'no status change';
    if ( $patron ) {
        if ( $cardStatus eq 'locked' ) {
            my $is_debarred = 0;
            my $debarrments = $patron->restrictions;
            while( my $debarment = $debarrments->next ) {
                my $debartype = $debarment->type->code;
                if ( 
                      $debartype eq $debarmentType &&
                      (!$debarment->expiration || dt_from_string( $debarment->expiration ) > dt_from_string) 
                ) 
                {
                    $is_debarred = 1;
                }
                elsif ( $debartype eq $debarmentType && $debarment->expiration ) 
                {
                    $debarment->expiration(undef);
                    $debarment->store;
                    $is_debarred = 1;
                }
            }
            if (! $is_debarred ) {
                AddDebarment(
                    {   borrowernumber => $patron->borrowernumber,
                        type           => $debarmentType,
                        comment        => $debarmentComment,
                        expiration     => undef,
                    }
                );
            }
        }
        if ( $cardStatus eq 'active' ) {
            my $debarrments = $patron->restrictions;
            while( my $debarment = $debarrments->next ) {
                my $debartype = $debarment->type->code;
                if ( $debartype eq $debarmentType ) 
                {
                    DelDebarment( $debarment->borrower_debarment_id );
                }
            }
        }
    } else {
        $result = 'patron not found';
    }
    return $result;
}

sub getForeignCards {
    my $self = shift;
    
    my $dbh = C4::Context->dbh;
    
    my @prefixes = @{$self->{prefixes}};
    
    my @cards;
    
    foreach my $prefix(@prefixes) {
        my $length = length($prefix);
        my $select = qq{
            SELECT cardnumber 
            FROM   borrowers
            WHERE  LEFT(cardnumber,$length) = ?
            ORDER BY cardnumber;
        };
        
        my $sth = $dbh->prepare($select);
        $sth->execute($prefix);
        
        while ( my ($cardnumber) = $sth->fetchrow_array ) {
            push @cards, $cardnumber;
        }
    }
    return @cards;
}

1;
