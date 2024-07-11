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

use Mojo::Base 'Mojolicious::Controller';

sub getCardStatus {
    my $c = shift->openapi->valid_input or return;
    my $cardNumber = $c->validation->output->{'card_number'};
    
    my $response = { card_number => $cardNumber, card_status => "active" };
    
    return $c->render(status  => 200, openapi => $response );
}

sub setCardStatus {
    my $c = shift->openapi->valid_input or return;
    
    my $body = $c->validation->param('body');
    my $cardNumber = $body->{card_number};
    my $cardStatus = $body->{card_status};
    
    my $response = { card_number => $cardNumber, card_status => $cardStatus };
    
    return $c->render(status  => 200, openapi => $response );
}

sub healthCheck {
    my $c = shift->openapi->valid_input or return;
    
    my $apikey = $c->req->headers->header('X-API-KEY');
    if ( $apikey eq 'YpLhYPpcR/7Nq2LCFptsacx/efCZ' ) {
        $apikey = 'key ok';
    }
    
    my $response = { status => "ok $apikey" };
    
    return $c->render(status  => 200, openapi => $response );
}

1;
