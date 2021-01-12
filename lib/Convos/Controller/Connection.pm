package Convos::Controller::Connection;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::Util 'trim';

sub create {
  my $self = shift->openapi->valid_input or return;
  my $user = $self->backend->user        or return $self->reply->errors([], 401);
  my $json = $self->req->json;

  my $url = Mojo::URL->new($json->{url} || '');
  $url->path("/$json->{conversation_id}") if $json->{conversation_id};
  $url->query->param(remote_address => $self->tx->remote_address);

  if ($self->settings('forced_connection')) {
    my $default_connection = Mojo::URL->new($self->settings('default_connection'));
    return $self->reply->errors('Will only accept forced connection URL.', 400)
      if $url->host_port ne $default_connection->host_port;
  }

  return $self->reply->errors('Missing "host" in URL', 400) unless $url->host;

  return $self->backend->connection_create_p($url)->then(
    sub {
      my $connection = shift;
      $connection->on_connect_commands($json->{on_connect_commands} || []);
      $connection->wanted_state($json->{wanted_state}) if $json->{wanted_state};
      $self->app->core->connect($connection);
      $self->render(openapi => $connection);
    },
    sub {
      $self->reply->errors(shift || 'Could not create connection.', 400);
    },
  );
}

sub list {
  my $self = shift->openapi->valid_input or return;
  my $user = $self->backend->user        or return $self->reply->errors([], 401);
  my @connections;

  for my $connection (sort { $a->name cmp $b->name } @{$user->connections}) {
    push @connections, $connection;
  }

  $self->render(openapi => {connections => \@connections});
}

sub remove {
  my $self = shift->openapi->valid_input or return;
  my $user = $self->backend->user        or return $self->reply->errors([], 401);

  return $user->remove_connection_p($self->stash('connection_id'))->then(sub {
    $self->render(openapi => {});
  });
}

sub update {
  my $self         = shift->openapi->valid_input or return;
  my $user         = $self->backend->user        or return $self->reply->errors([], 401);
  my $json         = $self->req->json;
  my $wanted_state = $json->{wanted_state} || '';
  my $connection;

  eval {
    $connection = $user->get_connection($self->stash('connection_id'));
    $connection->url->host or die 'Connection not found.';
    $connection->wanted_state($wanted_state) if $wanted_state;
    1;
  } or do {
    return $self->reply->errors('Connection not found.', 404);
  };

  if (my $cmds = $json->{on_connect_commands}) {
    $cmds = [map { trim $_} @$cmds];
    $connection->on_connect_commands($cmds);
  }

  my $url = Mojo::URL->new($json->{url} || '');
  $url = $connection->url unless $url->host;
  $url->query->param(remote_address => $self->tx->remote_address);

  unless ($self->settings('forced_connection')) {
    $url->scheme($json->{protocol} || $connection->url->scheme || '');
    $wanted_state = 'reconnect'
      if $wanted_state ne 'disconnected' and not _same_url($url, $connection->url);
    $connection->url($url);
  }

  my @p = ($connection->save_p);
  $wanted_state = '' if $connection->state eq 'connected' and $wanted_state eq 'connected';
  if ($wanted_state eq 'disconnected' or $wanted_state eq 'reconnect') {
    push @p, $connection->disconnect_p;
  }
  elsif ($url->query->param('nick')) {
    $connection->send_p('', sprintf '/nick %s', $url->query->param('nick'));
  }

  return Mojo::Promise->all(@p)->then(sub {
    $self->app->core->connect($connection)
      if $wanted_state eq 'connected' or $wanted_state eq 'reconnect';
    $self->render(openapi => $connection);
  });
}

sub _same_url {
  my ($u1, $u2) = @_;

  return 0 unless $u1->host_port eq $u2->host_port;
  return 0 unless +($u1->query->param('sasl') || '') eq +($u2->query->param('sasl') || '');
  return 0 unless +($u1->query->param('tls')  || '0') eq +($u2->query->param('tls') || '0');
  return 0 unless +($u1->userinfo // '') eq +($u2->userinfo // '');
  return 1;
}

1;

=encoding utf8

=head1 NAME

Convos::Controller::Connection - Convos connection actions

=head1 DESCRIPTION

L<Convos::Controller::Connection> is a L<Mojolicious::Controller> with
user related actions.

=head1 METHODS

=head2 create

See L<https://convos.chat/api.html#op-post--connections>

=head2 list

See L<https://convos.chat/api.html#op-get--connections>

=head2 remove

See L<https://convos.chat/api.html#op-delete--connection--connection_id->

=head2 update

See L<https://convos.chat/api.html#op-post--connection--connection_id->

=head1 SEE ALSO

L<Convos>.

=cut
