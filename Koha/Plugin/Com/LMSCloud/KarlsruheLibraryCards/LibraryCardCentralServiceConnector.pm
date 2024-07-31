package Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards::LibraryCardCentralServiceConnector;

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
use URI;
use LWP::UserAgent;
use JSON;

use Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards;

sub new {
    my ( $class ) = @_;
    
    my $self = {};
    bless $self, $class;
    
    my $plugin = Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards->new();
    my $serviceURL = $plugin->retrieve_data('kalib_service') || '';
    my $serviceKey = $plugin->retrieve_data('kalib_key') || '';
    
    $self->{serviceURL} = $serviceURL;
    $self->{serviceKey} = $serviceKey;
    
    return $self;
}

sub getCardStatus {
    my $self = shift;
    my $cardNumber = shift;
    
    my $json = JSON->new->utf8;
    my $response = { is_success => 0, is_error => 0, error_message => undef, card_number => $cardNumber, card_status => 'active', status => '200' };
    
    if ( $self->{serviceURL} && $self->{serviceKey} ) {
        my $serviceURI = $self->{serviceURL};
        my $serviceAPIKey = $self->{serviceKey};
        # check remote cards status
        $serviceURI =~ s/(\s|\/)+$//;
        $serviceURI .= "/card_status/$cardNumber";
        my $uri = URI->new($serviceURI);
        my $ua  = LWP::UserAgent->new(timeout => 5);
        
        my $resp = $ua->get(
                        $uri,
                        "accept" => "application/json",
                        "X-API-KEY" => "$serviceAPIKey",
                    );
                    
        $response->{status} = $resp->code;
        if ($resp->is_success) {
            my $content = $resp->content;
            my $result = $json->decode( $content );
            if ( $result && exists( $result->{card_number} ) && $result->{card_number} eq $cardNumber ) {
                if ( $result->{card_status} && $result->{card_status} eq 'locked' ) {
                    $response->{is_success} = 1;
                    $response->{card_status} = 'locked';
                }
                elsif ( $result->{card_status} && $result->{card_status} eq 'active' ) {
                    $response->{is_success} = 1;
                    $response->{card_status} = 'active';
                }
                elsif ( $result->{card_status} ) {
                    $response->{is_error} = 1;
                    $response->{error_message} = "Undexpected card status: " . $result->{card_status};
                }
                else {
                    $response->{is_error} = 1;
                    $response->{error_message} = "Undexpected check card response: " . $content;
                }
            } else {
                $response->{is_error} = 1;
                $response->{error_message} = "Undexpected check card response: " . $content;
            }
        } else {
            my $contentStruct;
            my $content = $resp->content;
            eval {
                $contentStruct = $json->decode( $content );
            };
            if ( $resp->code == 404 && $contentStruct && defined($contentStruct->{detail}) )  {
                $response->{is_error} = 1;
                $response->{error_message} = $contentStruct->{detail};
            }
            else {
                my $message = $resp->status_line;
                $message .= ". Error message: " . $content if ($content);
                $response->{is_error} = 1;
                $response->{error_message} = "Unable to retrieve card status using $serviceURI: $message";
            }
        }
    }
    else {
        $response->{is_error} = 1;
        $response->{error_message} = "Plugin configuration incomplete. Missing service URL and/or service key.";
    }
    return $response;
}

sub setCardStatus {
    my $self = shift;
    my $cardNumber = shift;
    my $cardStatus = shift;
    
    my $response = { is_success => 0, is_error => 0, error_message => undef, card_number => $cardNumber, card_status => 'active' };
    
    if ( $self->{serviceURL} && $self->{serviceKey} ) {
        my $serviceURI = $self->{serviceURL};
        my $serviceAPIKey = $self->{serviceKey};
        
        # check remote cards status
        $serviceURI =~ s/(\s|\/)+$//;
        $serviceURI .= "/card_status";
        
        my $uri = URI->new($serviceURI);
        my $json = JSON->new->utf8;
        my $content = { card_number => $cardNumber, card_status => $cardStatus };
        
        my $req = HTTP::Request->new( 'POST', $uri );
        $req->header( 'Content-Type' => 'application/json', 'accept' => 'application/json' , "X-API-KEY" => "$serviceAPIKey");
        $req->content( $json->encode( $content ) );
        
        my $ua  = LWP::UserAgent->new(timeout => 5);
        my $resp = $ua->request( $req );
        
        if ($resp->is_success) {
            my $json = JSON->new->utf8;
            my $content = $resp->content;
            my $result = $json->decode( $content );
            if ( $result && exists( $result->{card_number} ) && $result->{card_number} eq $cardNumber ) {
                if ( $result->{card_status} && $result->{card_status} eq 'locked' ) {
                    $response->{is_success} = 1;
                    $response->{card_status} = 'locked';
                }
                elsif ( $result->{card_status} && $result->{card_status} eq 'active' ) {
                    $response->{is_success} = 1;
                    $response->{card_status} = 'active';
                }
                elsif ( $result->{card_status} ) {
                    $response->{is_error} = 1;
                    $response->{error_message} = "Undexpected card status: " . $result->{card_status};
                }
                else {
                    $response->{is_error} = 1;
                    $response->{error_message} = "Undexpected check card response: " . $content;
                }
            } else {
                $response->{is_error} = 1;
                $response->{error_message} = "Undexpected check card response: " . $content;
            }
        } else {
            my $message = $resp->status_line;
            my $content = $resp->content;
            $message .= ". Error message: " . $content if ($content);
            $response->{is_error} = 1;
            $response->{error_message} = "Unable to set card status using $serviceURI: $message";
        }
    }
    else {
        $response->{is_error} = 1;
        $response->{error_message} = "Plugin configuration incomplete. Missing service URL and/or service key.";
    }
    return $response;
}
1;
