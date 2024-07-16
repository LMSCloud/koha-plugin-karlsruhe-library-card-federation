package Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardController;

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

use Net::IP;
use JSON qw( decode_json );

use Data::Dumper;

use Mojo::Base 'Mojolicious::Controller';
use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards;
use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardCentralServiceConnector;
use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::ForeignCardUpdater;
use Koha::Patrons;
use Koha::DateUtils qw( dt_from_string );

sub getCardStatus {
    my $c = shift->openapi->valid_input or return;
    
    my $apikey = $c->req->headers->header('X-API-KEY');
    my $ip = $c->req->headers->header('X-Forwarded-For') || '';
    my $plugin = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards->new();
    if (! checkApiKey($plugin,$apikey,$ip) ) {
        return $c->render(status  => 401, openapi => { detail => "Unauthorized access." } );
    }
    
    my $cardNumber = $c->validation->output->{'card_number'} || '';
    my $localPrefix = $plugin->retrieve_data('local_prefix') || '';
    my $debarmentTypes = $plugin->retrieve_data('local_debarment_types') || '';
    
    if ( !$cardNumber || length($cardNumber) != 12 ) {
        return $c->render(status  => 400, openapi => { detail => "Card Number not valid." } );
    }
    
    if ( $cardNumber !~ /^$localPrefix/ ) {
        return $c->render(status  => 400, openapi => { detail => "No local card number." } );
    }
    
    my $patron = Koha::Patrons->find( { cardnumber => $cardNumber } );
    
    my $response = { card_number => $cardNumber, card_status => "active" };
    if ( $patron ) {
        my @debarmentTypeList = map  {   
                                        s/^\s+//;  # strip leading spaces
                                        s/\s+$//;  # strip trailing spaces
                                        $_         # return the modified string
                                     }
                                     split(/\|/,$debarmentTypes);
        eval {
            my $debarrments = $patron->restrictions;
            while( my $debarment = $debarrments->next ) {
                my $debartype = $debarment->type->code;
                if ( 
                      grep(/^$debartype$/, @debarmentTypeList) &&
                      (!$debarment->expiration || dt_from_string( $debarment->expiration ) > dt_from_string) 
                ) 
                {
                    $response->{card_status} = 'locked';
                }
            }
        };
    } else {
        $response->{card_status} = 'locked';
    }
    
    return $c->render(status  => 200, openapi => $response );
}

sub setCardStatus {
    my $c = shift->openapi->valid_input or return;
    
    my $apikey = $c->req->headers->header('X-API-KEY');
    my $ip = $c->req->headers->header('X-Forwarded-For') || '';
    my $plugin = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards->new();
    if (! checkApiKey($plugin,$apikey,$ip) ) {
        return $c->render(status  => 401, openapi => { detail => "Unauthorized access." } );
    }
    
    my $body = $c->validation->param('body');
    my $cardNumber = $body->{card_number};
    my $cardStatus = $body->{card_status};
    
    my $checkPrefixes = $plugin->retrieve_data('kalib_prefixes') || '';
    my $debarmentType = $plugin->retrieve_data('set_debarment_type') || '';
    my $debarmentComment = $plugin->retrieve_data('set_debarment_comment');
    my $localPrefix = $plugin->retrieve_data('local_prefix') || '';
    
    if ( !$cardNumber || length($cardNumber) != 12 ) {
        return $c->render(status  => 400, openapi => { detail => "Card Number $cardNumber not valid." } );
    }
    my @checkPrefixList = map  {   
                                    s/^\s+//;  # strip leading spaces
                                    s/\s+$//;  # strip trailing spaces
                                    $_         # return the modified string
                                 }
                                 split(/\|/,$checkPrefixes);
    
    if ( (scalar(@checkPrefixList) == 0 || grep($cardNumber =~ /^$_/, @checkPrefixList)) && !($localPrefix && $cardNumber =~ /^$localPrefix/) ) {
        # check whether the $debarmentType is configured
        if ( $debarmentType ) {
            my $updater = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::ForeignCardUpdater->new();
            $updater->updateCardStatus($cardNumber,$cardStatus);
        }
    }
    
    my $response = { card_number => $cardNumber, card_status => $cardStatus };
    
    return $c->render(status  => 200, openapi => $response );
}

sub checkCardStatus {
    my $c = shift->openapi->valid_input or return;
    
    my $plugin = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards->new();
    my $checkPrefixes = $plugin->retrieve_data('kalib_prefixes') || '';
    my $localPrefix = $plugin->retrieve_data('local_prefix') || '';
    my $serviceURI = $plugin->retrieve_data('kalib_service') || '';
    my $serviceAPIKey = $plugin->retrieve_data('kalib_key') || '';
    
    my $cardNumber = $c->validation->output->{'card_number'} || '';
    
    my @checkPrefixList = map  {   
                                    s/^\s+//;  # strip leading spaces
                                    s/\s+$//;  # strip trailing spaces
                                    $_         # return the modified string
                                 }
                                 split(/\|/,$checkPrefixes);
    my $cardStatus = 'active';
    if ( $cardNumber && 
         length($cardNumber) == 12 && 
         (scalar(@checkPrefixList) == 0 || grep($cardNumber =~ /^$_/, @checkPrefixList)) 
         && !($localPrefix && $cardNumber =~ /^$localPrefix/)) 
    {
        my $cardService = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardCentralServiceConnector->new();
        my $result = $cardService->getCardStatus($cardNumber);
        
        if ( $result->{is_error} ) {
            if ( $result->{status} == 404 ) {
                return $c->render(status  => 404, openapi => { detail => $result->{error_message} } );
            }
            return $c->render(status  => 400, openapi => { detail => $result->{error_message} } );
        }
        if ( $result->{is_success} ) {
            $cardStatus = $result->{card_status};
        }
    }
    
    my $response = { card_number => $cardNumber, card_status => $cardStatus };
    
    return $c->render(status  => 200, openapi => $response );
}

sub healthCheck {
    my $c = shift->openapi->valid_input or return;
    
    my $apikey = $c->req->headers->header('X-API-KEY');
    my $ip = $c->req->headers->header('X-Forwarded-For') || '';
    my $plugin = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards->new();
    if (! checkApiKey($plugin,$apikey,$ip) ) {
        return $c->render(status  => 401, openapi => { detail => "Unauthorized access." } );
    }
    
    my $response = { status => "ok" };
    
    return $c->render(status  => 200, openapi => $response );
}

sub checkApiKey {
    my $plugin = shift;
    my $apikey = shift;
    my $clientIP = shift;
    
    my $retval = 0;
    if ( $apikey ) {
        my $keyconfigs = decode_json($plugin->retrieve_data('api_keys') || '[]');
        foreach my $keyconfig (@$keyconfigs) {
            my $checkkey = $keyconfig->{apikey};
            if ( $apikey eq $checkkey ) {
                $retval = 1;
            }
        }
        my $iplist = $plugin->retrieve_data('ip_check') || '';
        $iplist =~ s/(^\s+|\s+$)// if ($iplist);
        if ( $retval && $iplist ) {
            my @ips = split(/\|/,$iplist);
            
            my $checkip = new Net::IP($clientIP);
            my $ipcheck = 0;
            my $ipchecked = 0;
            foreach my $ip(@ips) {
                $ip =~ s/(^\s+|\s+$)// if ($ip);
                
                if ( $ip) {
                    $ipchecked = 1;
                    my $iprange = new Net::IP($ip);
                    if ( $iprange ) {
                        my $res = $iprange->overlaps($checkip);
                        if ( $res == $IP_B_IN_A_OVERLAP || $res == $IP_IDENTICAL ) {
                           $ipcheck = 1;
                        }
                    }
                }
            }
            if ( $ipcheck == 0 && $ipchecked == 1  ) {
                $retval = 0;
            }
        }
    }
    return $retval;
}

1;
