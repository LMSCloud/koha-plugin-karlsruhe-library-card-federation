package Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardBatchStatusPusher;

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

use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardCentralServiceConnector;
use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardChangeDetector;
use C4::Context;

use Log::Log4perl;
use JSON qw( encode_json );

sub new {
    my ( $class ) = @_;
    
    my $self = {};
    bless $self, $class;
    
    my $plugin = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards->new();
    my $prefix = $plugin->retrieve_data('local_prefix') || '';
    my $table  = $plugin->get_qualified_table_name('cardnumber_status');
    
    $self->{prefix} = $prefix;
    $self->{pusher} = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardCentralServiceConnector->new();
    $self->{table}  = $table;
    
    my $logdir  = C4::Context->config('logdir');
    
    # Initialize Logger
    my $log_conf = qq(
       log4perl.rootLogger              = INFO, KALIB
       log4perl.appender.KALIB           = Log::Log4perl::Appender::File
       log4perl.appender.KALIB.filename  = $logdir/cardlib-pusher.log
       log4perl.appender.KALIB.mode      = append
       log4perl.appender.KALIB.layout    = Log::Log4perl::Layout::PatternLayout
       log4perl.appender.KALIB.layout.ConversionPattern = [%d] [%p] %m %n
       log4perl.appender.KALIB.utf8=1
    );
    Log::Log4perl::init(\$log_conf);
    my $logger = Log::Log4perl->get_logger();
    
    $self->{logger} = $logger;
    
    return $self;
}

sub pushStatusUpdates {
    my $self = shift;
    
    my $updateDetector = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardChangeDetector->new();
    
    my $newDebarredCards = $updateDetector->getNewDebarredCards();
    foreach my $cardNumber(sort keys %$newDebarredCards) {
        if ( ! $newDebarredCards->{$cardNumber} ) {
            # Send status locked
            # Insert with local cardstatus = 'locked'
            $self->pushStatusUpdateAndSetLocalStatus({ card_number => $cardNumber, send_card_status => 'locked', insert => 'locked', type => 'new inserted but debarred card' });
        }
        else {
            # Send status locked
            # Set local cardstatus = 'locked'
            $self->pushStatusUpdateAndSetLocalStatus({ card_number => $cardNumber, send_card_status => 'locked', set => 'locked', type => 'card with new debarment' });
        }
    }
    
    my $deletedDebarmentCards = $updateDetector->getDeletedDebarmentCards();
    foreach my $cardNumber(sort keys %$deletedDebarmentCards) {
        if ( $deletedDebarmentCards->{$cardNumber} eq 'active' ) {
            # Send status active
            # Set local cardstatus = 'active'
            $self->pushStatusUpdateAndSetLocalStatus({ card_number => $cardNumber, send_card_status => 'active', set => 'active', type => 'active card deleted debarment' });
        }
        else {
            # Set local cardstatus = 'deleted'
            $self->pushStatusUpdateAndSetLocalStatus({ card_number => $cardNumber, set => 'deleted', type => 'deleted card with previous debarment' });
        }
    }
    
    my $newOrReactivatedCards = $updateDetector->getNewOrReactivatedCards();
    foreach my $cardNumber(sort keys %$newOrReactivatedCards) {
        if ( $newOrReactivatedCards->{$cardNumber} eq 'active' ) {
            # Send status active
            # Insert with local cardstatus = 'active'
            $self->pushStatusUpdateAndSetLocalStatus({ card_number => $cardNumber, send_card_status => 'active', insert => 'active', type => 'new active card' });
        }
        else {
            # Send status active
            # Set local cardstatus = 'active'
            $self->pushStatusUpdateAndSetLocalStatus({ card_number => $cardNumber, send_card_status => 'active', set => 'active', type => 'reactivated card number' });
        }
    }
    
    my $deletedCards = $updateDetector->getDeletedCards();
    foreach my $cardNumber(sort keys %$deletedCards) {
        if ( $deletedCards->{$cardNumber} eq 'deleted' ) {
            # Send status locked
            # Set local cardstatus = 'deleted'
            $self->pushStatusUpdateAndSetLocalStatus({ card_number => $cardNumber, send_card_status => 'locked', set => 'active', type => 'deleted card number' });
        }
    }
}

sub pushStatusUpdateAndSetLocalStatus {
    my $self = shift;
    my $statusData = shift;
    
    my $cardnumber  = $statusData->{card_number};
    my $localPrefix = $self->{prefix};
    my $pushstatus  = 1;
    
    my $logger = $self->{logger};
    
    $logger->info("Processing status new update: " . encode_json($statusData));
    
    if ( $cardnumber && length($cardnumber) == 12 && $cardnumber =~ /^$localPrefix/ && exists($statusData->{send_card_status}) ) {
        my $result = $self->{pusher}->setCardStatus($cardnumber,$statusData->{send_card_status});
        
        if ( $result->{is_error} ) {
            $pushstatus = 0;
            $logger->error("Pushed status update with result: " . encode_json($result));
        } else {
            $logger->info("Pushed status update with result: " . encode_json($result));
        }
    }
    
    if ( $pushstatus == 1 && $cardnumber && exists($statusData->{insert}) ) {
        my $dbh = C4::Context->dbh;
        my $table = $self->{table};
        my $cardstatus = $statusData->{insert};
        my $res = $dbh->do("INSERT INTO $table (cardnumber,cardstatus) VALUES (?,?)",undef,$cardnumber,$cardstatus);
        $logger->info("Inserted new cardnumber status ($cardnumber,$cardstatus) to table $table with result: $res");
    }
    
    if ( $pushstatus == 1 && $cardnumber && exists($statusData->{set}) ) {
        my $dbh = C4::Context->dbh;
        my $table = $self->{table};
        my $cardstatus = $statusData->{set};
        my $res = $dbh->do("UPDATE $table SET cardstatus = ? WHERE cardnumber = ?",undef,$cardstatus,$cardnumber);
        $logger->info("Updated cardnumber status ($cardnumber,$cardstatus) of table $table with result: $res");
    }
}

1;
