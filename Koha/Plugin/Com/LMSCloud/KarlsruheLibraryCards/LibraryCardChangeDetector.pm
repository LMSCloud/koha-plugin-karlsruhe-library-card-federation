package Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardChangeDetector;

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
use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards;
use C4::Context;

sub new {
    my ( $class ) = @_;
    
    my $self = {};
    bless $self, $class;
    
    my $plugin = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards->new();
    my $debarmentTypes = $plugin->retrieve_data('local_debarment_types') || '';
    
    $debarmentTypes =~ s/(^\s+|\s+$)//g;
    my @debarmentTypeList = map  {   
                                    s/^\s+//;  # strip leading spaces
                                    s/\s+$//;  # strip trailing spaces
                                    $_         # return the modified string
                                 }
                                 split(/\|/,$debarmentTypes);
                                 
    my @placeholder = ('?') x scalar(@debarmentTypeList);
    
    $self->{debarmentType} = $debarmentTypes;
    $self->{debarmentTypeList} = \@debarmentTypeList;
    $self->{debarmentPlacholder} = join(',',@placeholder);
    
    return $self;
}

sub getNewDebarredCards {
    my $self = shift;
    my $dbh = C4::Context->dbh;
    
    my $debarredNew = {};
    
    return $debarredNew if (! $self->{debarmentType} );
    
    my @debarmentTypeList = @{$self->{debarmentTypeList}};
    my $placeholder = $self->{debarmentPlacholder};

    my $select = qq{
      SELECT b.cardnumber,
             st.cardstatus
      FROM   borrowers b
             LEFT JOIN koha_plugin_com_lmscloud_karlsruhelibrarycards_cardnumber_status st ON (st.cardnumber = b.cardnumber)
      WHERE  b.cardnumber <> '' 
        AND  b.cardnumber IS NOT NULL
        AND  EXISTS (SELECT 1 
                     FROM   borrower_debarments bd
                     WHERE  b.borrowernumber = bd.borrowernumber
                       AND  bd.type IN ($placeholder)
                       AND  (expiration IS NULL OR expiration > CURDATE())
                    )
         AND NOT EXISTS (SELECT 1
                         FROM   koha_plugin_com_lmscloud_karlsruhelibrarycards_cardnumber_status kb
                         WHERE  kb.cardnumber = b.cardnumber
                            AND kb.cardstatus = 'locked')
    };
    
    my $sth = $dbh->prepare($select);
    $sth->execute(@debarmentTypeList);
    
    while ( my ($cardnumber,$cardstatus) = $sth->fetchrow_array ) {
        $debarredNew->{$cardnumber} = $cardstatus;
    }
    return $debarredNew;
}

sub getDeletedDebarmentCards {
    my $self = shift;
    my $dbh = C4::Context->dbh;
    
    my $debarredDeleted = {};
    
    return $debarredDeleted if (! $self->{debarmentType} );

    my @debarmentTypeList = @{$self->{debarmentTypeList}};
    my $placeholder = $self->{debarmentPlacholder};
    
    my $select = qq{
      SELECT st.cardnumber,
             IF (borr.borrowernumber IS NULL,'deleted','active') AS 'cardstatus'
      FROM   koha_plugin_com_lmscloud_karlsruhelibrarycards_cardnumber_status st
             LEFT JOIN borrowers borr ON (borr.cardnumber = st.cardnumber)
      WHERE  st.cardstatus = 'locked'
        AND  NOT EXISTS (SELECT 1 
                         FROM   borrower_debarments bd
                                JOIN borrowers b ON (b.cardnumber = st.cardnumber)
                         WHERE  b.borrowernumber = bd.borrowernumber
                           AND  bd.type IN ($placeholder)
                           AND  (expiration IS NULL OR expiration > CURDATE())
                        )
    };
    
    my $sth = $dbh->prepare($select);
    $sth->execute(@debarmentTypeList);
    
    while ( my ($cardnumber,$cardstatus) = $sth->fetchrow_array ) {
        $debarredDeleted->{$cardnumber} = $cardstatus;
    }
    return $debarredDeleted;
}

sub getNewOrReactivatedCards {
    my $self = shift;
    my $dbh = C4::Context->dbh;
    
    my $newOrReactivated = {};
    
    my @debarmentTypeList = @{$self->{debarmentTypeList}};
    my $placeholder = $self->{debarmentPlacholder};

    my $select = qq{
      SELECT cardnumber,
             'active' AS cardstatus
      FROM   borrowers b
      WHERE  b.cardnumber <> '' 
         AND b.cardnumber IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM koha_plugin_com_lmscloud_karlsruhelibrarycards_cardnumber_status kb WHERE kb.cardnumber = b.cardnumber)
    };
    $select .= qq{
         AND NOT EXISTS (SELECT 1 
                         FROM   borrower_debarments bd
                         WHERE  b.borrowernumber = bd.borrowernumber
                           AND  bd.type IN ($placeholder)
                           AND  (expiration IS NULL OR expiration > CURDATE())
                        )
    } if ($self->{debarmentType});
    $select .= qq{
      UNION
      SELECT st.cardnumber,
             'deleted' AS cardstatus
      FROM   koha_plugin_com_lmscloud_karlsruhelibrarycards_cardnumber_status st
             JOIN borrowers b ON (b.cardnumber = st.cardnumber)
      WHERE  st.cardstatus = 'deleted'
    };
    $select .= qq{
        AND  NOT EXISTS (SELECT 1 
                         FROM   borrower_debarments bd
                         WHERE  b.borrowernumber = bd.borrowernumber
                           AND  bd.type IN ($placeholder)
                           AND  (expiration IS NULL OR expiration > CURDATE())
                        )
    } if ($self->{debarmentType});
    
    my $sth = $dbh->prepare($select);
    
    if ( $self->{debarmentType} ) {
        $sth->execute(@debarmentTypeList,@debarmentTypeList);
    } else {
        $sth->execute();
    }
    
    while ( my ($cardnumber,$cardstatus) = $sth->fetchrow_array ) {
        $newOrReactivated->{$cardnumber} = $cardstatus;
    }
    return $newOrReactivated;
}

sub getDeletedCards {
    my $self = shift;
    my $dbh = C4::Context->dbh;
    
    my $deleted = {};

    my $select = qq{
      SELECT kb.cardnumber,
             'deleted' AS cardstatus
      FROM   koha_plugin_com_lmscloud_karlsruhelibrarycards_cardnumber_status kb
      WHERE  cardstatus = 'active' AND 
             NOT EXISTS (SELECT 1 FROM borrowers b WHERE b.cardnumber = kb.cardnumber)
    };
    
    my $sth = $dbh->prepare($select);
    $sth->execute();
    
    while ( my ($cardnumber,$cardstatus) = $sth->fetchrow_array ) {
        $deleted->{$cardnumber} = $cardstatus;
    }
    return $deleted;
}

1;
