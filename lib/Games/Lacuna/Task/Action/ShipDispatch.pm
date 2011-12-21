package Games::Lacuna::Task::Action::ShipDispatch;

use 5.010;

use Moose;
# -traits => 'NoAutomatic';
extends qw(Games::Lacuna::Task::Action);
with qw(Games::Lacuna::Task::Role::PlanetRun
    Games::Lacuna::Task::Role::Ships);

use Games::Lacuna::Task::Utils qw(normalize_name);

sub description {
    return q[Dispatch ships based on their name];
}

has '_planet_re' => (
    is              => 'rw',
    isa             => 'RegexpRef',
    lazy_build      => 1,
    builder         => '_build_planet_re',
    traits          => ['NoIntrospection','NoGetopt'],
);

sub _build_planet_re {
    my ($self) = @_;
    
    my @list;
    foreach my $body ($self->my_planets) {
        push(@list,$body->{id});
        push(@list,uc($body->{name}));
        push(@list,normalize_name($body->{name}));
    }
    
    my $string = join('|', map { "\Q$_\E" } @list);
    return qr/\b ($string) \b/x;
}


sub process_planet {
    my ($self,$planet_stats) = @_;
    
    # Get space port
    my $spaceport_object = $self->get_building_object($planet_stats->{id},'SpacePort');
    my $trade_object = $self->get_building_object($planet_stats->{id},'Trade');
    return 
        unless $spaceport_object && $trade_object;
    
    # Get all available ships
    my $ships_data = $self->request(
        object  => $spaceport_object,
        method  => 'view_all_ships',
        params  => [ { no_paging => 1 }, { task => [ 'Docked' ] } ],
    );
    
    my %dispatch;
    
    SHIPS:
    foreach my $ship (@{$ships_data->{ships}}) {
        # Dispatch to another planet
        if ( uc($ship->{name}) =~ $self->_planet_re ) {
            my $target_planet = $self->my_body_status($1);
            next SHIPS
                if $target_planet->{id} == $planet_stats->{id};
            
            $dispatch{$target_planet->{id}} ||= [];
            push (@{$dispatch{$target_planet->{id}}},$ship);
            
            $self->log('notice','Dispatching ships from %s to %s',$ship->{name},$planet_stats->{name},$target_planet->{name});
        # Scuttle
        } elsif ( $ship->{name} =~ m/\b(scuttle|demolish)\b/) {
            $self->log('notice','Scuttling ship %s on %s',$ship->{name},$planet_stats->{name});
            
            $self->request(
                object  => $spaceport_object,
                method  => 'scuttle_ship',
                params  => [$ship->{id}],
            );
        # Start mining
        } elsif ( $ship->{name} =~ m/\b(mining|miner)\b/) {
            $self->log('notice','Starting to mine with ship %s on %s',$ship->{name},$planet_stats->{name});
            
            my $mining_object = $self->get_building_object($planet_stats->{id},'MiningMinistry');
            
            $self->request(
                object  => $mining_object,
                method  => 'add_cargo_ship_to_fleet',
                params  => [$ship->{id}],
            );
        }
    }
    
    foreach my $body_id (sort { scalar(@{$dispatch{$a}}) <=> scalar(@{$dispatch{$b}}) }keys %dispatch) {
        
        my @ships = @{$dispatch{$body_id}};
        
        no warnings 'once';
        my $trade_cargo = scalar(@ships) * $Games::Lacuna::Task::Constants::CARGO{ship};
        
        # Get trade ship
        my $trade_ship_id = $self->trade_ships($planet_stats->{id},$trade_cargo);
        
        return
            unless $trade_ship_id;
        
        my @push_ships;
        
        foreach my $ship (@ships) {
            my $name = $ship->{name};
            
            # Replace one exclamation mark
            $name =~ s/!//;
            
            if ($name ne $ship->{name}) {
                $self->request(
                    object  => $spaceport_object,
                    method  => 'name_ship',
                    params  => [$ship->{id},$name],
                );
            }
            
            push (@push_ships,{
                "type"      => "ship",
                "ship_id"   => $ship->{id},
            });
        }
        
        my $response = $self->request(
            object  => $trade_object,
            method  => 'push_items',
            params  => [ $body_id, \@push_ships, { ship_id => $trade_ship_id } ]
        );
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;