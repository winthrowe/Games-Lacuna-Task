package Games::Lacuna::Task::Action::OptimizeProbes;

use 5.010;

use Moose -traits => 'NoAutomatic';
extends qw(Games::Lacuna::Task::Action);
with qw(Games::Lacuna::Task::Role::PlanetRun
    Games::Lacuna::Task::Role::Stars);

sub description {
    return q[Checks for duplicate probes];
}

has '_star_cache' => (
    is              => 'rw',
    isa             => 'HashRef',
    required        => 1,
    default         => sub { {} },
    traits          => ['Hash','NoIntrospection','NoGetopt'],
    handles         => {
        add_star_cache     => 'set',
        has_star_cache     => 'exists',
    }
);

sub process_planet {
    my ($self,$planet_stats) = @_;
        
    # Get observatory
    my $observatory = $self->find_building($planet_stats->{id},'Observatory');
    
    return 
        unless $observatory;
    
    # Get observatory probed stars
    my $observatory_object = $self->build_object($observatory);
    my $observatory_data = $self->paged_request(
        object  => $observatory_object,
        method  => 'get_probed_stars',
        total   => 'star_count',
        data    => 'stars',
    );
    
    foreach my $star (@{$observatory_data->{stars}}) {
        my $star_id = $star->{id};
        my $has_star_cache = $self->has_star_cache($star_id);
        if ($has_star_cache) {
            $self->log('notice',"Abandoning probe from %s in %s",$planet_stats->{name},$star->{name});
            $self->request(
                object  => $observatory_object,
                method  => 'abandon_probe',
                params  => [$star_id],
            );
            # Check star status
            $self->get_star_api_area_by_id($star_id);
        } else {
            $self->add_star_cache($star_id,1);
        }
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;