package Koha::Plugin::Com::LMSCloud::KarlsruheLibraryCards;

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

use base qw(Koha::Plugins::Base);

use C4::Context;

our $VERSION = "0.0.7";

our $metadata = {
    name            => 'Karlsruhe Library Card Federation Plugin',
    author          => 'LMSCloud GmbH',
    date_authored   => '2024-07-09',
    date_updated    => '2024-07-15',
    minimum_version => '22.11.15.011',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin implements API endpoints required'
                     . ' for the Karlsruhe library federation to verify and set'
                     . ' status of library cards.'
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_dir = $self->mbf_dir();

    my $schema = JSON::Validator::Schema::OpenAPIv2->new;
    my $spec = $schema->resolve($spec_dir . '/openapi.yaml');

    return $self->_convert_refs_to_absolute($spec->data->{'paths'}, 'file://' . $spec_dir . '/');
}

sub api_namespace {
    my ( $self ) = @_;

    return 'kalibfed';
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });
        
        my $apikeys = $self->retrieve_data('api_keys');
        
        if ( !$apikeys ) {
            my @alphanumeric = ('a'..'z', 'A'..'Z', 0..9, '_', '-', '%', '/', '&', '?');
            my $randpassword = join '', map $alphanumeric[rand @alphanumeric], 0..35;
        
             $apikeys =     "[\n" .
                            "    {\n" . 
                            "        \"apikey\": \"$randpassword\",\n" .
                            "        \"description\": \"Sample key to access the local service\"\n" .
                            "    }\n" .
                            "]\n";
        }

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            api_keys               => $apikeys,
            local_prefix           => $self->retrieve_data('local_prefix'),
            kalib_prefixes         => $self->retrieve_data('kalib_prefixes'),
            kalib_service          => $self->retrieve_data('kalib_service'),
            kalib_key              => $self->retrieve_data('kalib_key'),
            ip_check               => $self->retrieve_data('ip_check'),
            local_debarment_types  => $self->retrieve_data('local_debarment_types'),
            set_debarment_type     => $self->retrieve_data('set_debarment_type'),
            set_debarment_comment  => $self->retrieve_data('set_debarment_comment'),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                api_keys               => $cgi->param('api_keys'),
                local_prefix           => $cgi->param('local_prefix'),
                kalib_prefixes         => $cgi->param('kalib_prefixes'),
                kalib_service          => $cgi->param('kalib_service'),
                kalib_key              => $cgi->param('kalib_key'),
                ip_check               => $cgi->param('ip_check'),
                local_debarment_types  => $cgi->param('local_debarment_types'),
                set_debarment_type     => $cgi->param('set_debarment_type'),
                set_debarment_comment  => $cgi->param('set_debarment_comment'),
            }
        );
        $self->go_home();
    }
}

# Mandatory even if does nothing
sub install {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('cardnumber_status');

    C4::Context->dbh->do( "
        CREATE TABLE IF NOT EXISTS $table (
            `cardnumber` varchar(32) NOT NULL COMMENT 'card number of Koha accounts',
            `cardstatus` enum('active','deleted','locked') NOT NULL COMMENT 'status of the cards',
            `updated_on` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'time of last update',
            PRIMARY KEY (`cardnumber`),
            KEY `updated_on` (`updated_on`)
        ) ENGINE = INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    " );
    
    C4::Context->dbh->do( "
        INSERT IGNORE INTO $table (cardnumber,cardstatus)
        SELECT cardnumber, 'active'
        FROM borrowers b
        WHERE b.cardnumber <> '' AND b.cardnumber IS NOT NULL
    " );
    
    C4::Context->dbh->do( "
        INSERT IGNORE INTO $table (cardnumber,cardstatus)
        SELECT cardnumber, 'deleted'
        FROM deletedborrowers b
        WHERE b.cardnumber <> '' AND b.cardnumber IS NOT NULL
    " );
    
    return 1;
}

# Mandatory even if does nothing
sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

# Mandatory even if does nothing
sub uninstall {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('cardnumber_status');

    C4::Context->dbh->do("DROP TABLE IF EXISTS $table");
    return 1;
}

sub _convert_refs_to_absolute {
    my ( $self, $hashref, $path_prefix ) = @_;

    foreach my $key (keys %{ $hashref }) {
        if ($key eq '$ref') {
            if ($hashref->{$key} =~ /^(\.\/)?openapi/) {
                $hashref->{$key} = $path_prefix . $hashref->{$key};
            }
        } elsif (ref $hashref->{$key} eq 'HASH' ) {
            $hashref->{$key} = $self->_convert_refs_to_absolute($hashref->{$key}, $path_prefix);
        } elsif (ref($hashref->{$key}) eq 'ARRAY') {
            $hashref->{$key} = $self->_convert_array_refs_to_absolute($hashref->{$key}, $path_prefix);
        }
    }
    return $hashref;
}

sub _convert_array_refs_to_absolute {
    my ( $self, $arrayref, $path_prefix ) = @_;

    my @res;
    foreach my $item (@{ $arrayref }) {
        if (ref($item) eq 'HASH') {
            $item = $self->_convert_refs_to_absolute($item, $path_prefix);
        } elsif (ref($item) eq 'ARRAY') {
            $item = $self->_convert_array_refs_to_absolute($item, $path_prefix);
        }
        push @res, $item;
    }
    return \@res;
}

sub intranet_js {
    my ( $self ) = @_;
    
    my $checkPrefixes = $self->retrieve_data('kalib_prefixes');
    my @checkPrefixList = map  {   
                                s/^\s+//;  # strip leading spaces
                                s/\s+$//;  # strip trailing spaces
                                $_         # return the modified string
                             }
                             split(/\|/,$checkPrefixes);
    $checkPrefixes = '';
    if ( @checkPrefixList ) {
        $checkPrefixes = '&& currentValue.match(/^(' . join('|',@checkPrefixList) . ')/)';
    }
    return q!
<script>
$(document).ready(function(){
    if ( $("#pat_memberentrygen #cardnumber").length ) {
        $('#pat_memberentrygen #cardnumber').after('<span id="checkKALibCard" style="margin-left:1em"><a role="button" class="btn btn-sm btn-primary" onclick="checkKALibCard();return false;" disabled>KA-Ausweis pr&uuml;fen</a></span>');
        $("#pat_memberentrygen #cardnumber").keyup(function(e) {
            enableDisableCheckKALibCard();
        });
        enableDisableCheckKALibCard();
    }
});
function enableDisableCheckKALibCard() {
    var currentValue = $("#pat_memberentrygen #cardnumber").val();
    if( currentValue.length == 12 ! . ($checkPrefixes || '') . q!) {
        $("#pat_memberentrygen #checkKALibCard a").css('pointer-events','all').removeAttr('disabled');
    }
    else {
        $("#pat_memberentrygen #checkKALibCard a").css('pointer-events','none').attr('disabled','disabled');
   }
}
function checkKALibCard() {
    var cardNumber = $("#pat_memberentrygen #cardnumber").val();
    $.ajax({
              type: 'GET',
              url: '/api/v1/contrib/kalibfed/check_card_status/' + cardNumber,
              success: function (data) {
              	  var message;
                  if ( data.card_status == 'active' ) {
                      message = '<div class="alert alert-success" role="alert">' + 
                                'Der Ausweis ist g&uuml;ltig.' +
                                '</div>';
                  }
                  else if ( data.card_status == 'locked' ) {
                      message = '<div class="alert alert-danger" role="alert">' + 
                                'Der Ausweis ist gesperrt.' +
                                '</div>';
                  }
                  else {
                      message = '<div class="alert alert-warning" role="alert">' + 
                                'Es konnte kein g&uuml;ltiger Status des Ausweises ermittelt werden.' +
                                '</div>';
                  }
                  showKALibCardCheckResult(message,cardNumber);
              },
              error: function (data) {
              	  var error = data.responseJSON;
                  console.log(data);
                  var message = 
                            '<div class="alert alert-warning" role="alert">' +
                            'Bei der Abfrage des Kartenstatus trat ein Fehler auf.<br>' + 
                            error.detail + 
                            '</div>';
                  if ( data.status == 404 ) {
                       message = 
                            '<div class="alert alert-danger" role="alert">' +
                            'Diese Karte ist nicht g&uuml;ltig. Es wurden keine Informationen zu der Kartennummer ' + cardNumber + ' gefunden.' +
                            '</div>';
                  }
                  showKALibCardCheckResult(message,cardNumber);
              },
    });
}
function showKALibCardCheckResult(displayMessage,cardNumber) {
    var popupTemplate =
        '<div class="modal" id="kalibStatusMessage_dialog" tabindex="-1" role="dialog" aria-labelledby="kalibStatusMessage_label" aria-hidden="true">' +
        '  <div class="modal-dialog">' +
        '    <div class="modal-content">' +
        '      <div class="modal-header">' +
        '        <button type="button" class="kalibStatusMessage_close closebtn" data-dismiss="modal" aria-hidden="true">&times;</button>' +
        '        <h3 id="kalibStatusMessage_title">Ergebnis der KA-Ausweispr&uuml;fung f&uuml;r ' + cardNumber + '</h3>' +
        '      </div>' +
        '      <div class="modal-body">' +
        '      <p><div id="kalibStatusMessage_message">' + displayMessage + '</div><p>' +
        '      <div class="modal-footer">' +
        '        <button type="button" class="btn btn-small kalibStatusMessage_close" data-dismiss="modal">Schliessen</button>' +
        '      </div>' +
        '    </div>' +
        '  </div>' +
        '</div>';
    $(popupTemplate).modal();
    $(popupTemplate).show();
}
</script>
    !;
}

1;
