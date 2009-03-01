package Uta::Base;
use parent qw/Class::Accessor::Fast::XS Class::Data::Inheritable/;

use utf8;
use strict;
use CGI::Carp qw/croak carp/;

__PACKAGE__->mk_classdata(
  qw/conf/
);

__PACKAGE__->mk_accessors(
  qw/r req path_to stat_code stat_header template cache res session/
);

#------------------------------------------------------------------------
# new instance
# * 
#------------------------------------------------------------------------
sub new {
  return bless $_[1], $_[0];
}

#------------------------------------------------------------------------
# prepare values
# * set default values
#------------------------------------------------------------------------
sub prepare {
  my $self = shift;
  
  # status code
  $self->stat_code(Apache2::Const::OK);
  
  # テンプレート再利用(PLUGIN_BASE => 'Uta::Template', )
  $self->template(Template->new({ ABSOLUTE => 1, ENCODING => 'UTF-8' }));
  
  # キャッシュ
  $self->cache(Cache::Memcached::Fast->new({servers => ['127.0.0.1:11211'], compress_threshold => 10_000}));
  
  # 出力値
  $self->res({});
  $self->res->{conf}    = $self->conf;
  $self->res->{req}     = $self->req;
  $self->res->{wrapper} = $self->path_to.'/app/views/application/wrapper.tt';
  
  # セッション
  $self->session(CGI::Session->new('driver:File', $self->req->{cookie}{CGISESSID}, { Directory => $self->path_to.'/tmp/session' }));
  
  # クッキーが無効な場合
#  unless ($ENV{'HTTP_COOKIE'}) {
#    $self->error('Cookie is not defined');
#  }
}

#------------------------------------------------------------------------
# execute action
# * 
#------------------------------------------------------------------------
sub execute {
  my $self = shift;
  
  # check before filter
  my $filter = '__bfilter';
  if ($self->can($filter)) {
    $self->$filter();
  }
  
  # execute control
  my $action = $self->req->{action};
  if ($self->can($action)) {
    $self->$action();
  }
=pod
  # check after filter
  my $filter = '__afilter';
  # check after filter
  if ($self->can($filter)) {
    $self->$filter();
  }
=cut
  # template
  my $template_file = $self->path_to.'/app/views/'.$self->req->{controller}.'/'.$action.'.tt';
  $self->view($template_file);
}

#------------------------------------------------------------------------
# set template file
# * 
#------------------------------------------------------------------------
sub view {
  my $self = shift;
  my $filename = shift;
  my $registto = shift;
  my $html;
  
  # processing output
  if (-e $filename) {
    unless (defined $registto) {
      # override response parameter
      if ($self->can('__add_res_param')) {
        $self->__add_res_param();
      }
      # processing template
      $self->template->process($filename, $self->res, \$html) || $self->error('template error!', $self->template->error());
      if ($self->stat_header == undef) {
        $self->r->content_type('text/html;charset=utf-8;');
        $self->r->headers_out->add('Set-Cookie' => 'CGISESSID='.$self->session->id().';expires=Thu, 1-Jan-2030 00:00:00 GMT;path=/;');
        $self->stat_header(1);
      }
      $self->r->print($html);
    }
    else {
      $self->template->process($filename, $self->res, \$html) || $self->error('output template error!', $self->template->error());
      
      open my $FILE, '>'.$registto;
      print $FILE Encode::encode('utf-8', $html);
      close $FILE;
    }
  }
  else {
    $self->error('template not exists!');
  }
}

#------------------------------------------------------------------------
# error
# * error_msg : output error message
#------------------------------------------------------------------------
sub error {
  my $self = shift;
  my $filename = $self->path_to.'/app/views/application/error.tt';
  
  $self->res->{error_code} = shift;
  $self->res->{debug_code} = shift;
  
  $self->view($filename);
  
  goto END_LINE;
}

#------------------------------------------------------------------------
# page redirect
# * location : redirect uri
# * encode_flag : encoding?
#------------------------------------------------------------------------
sub uri_for {
  my($self, $location, $encode_flag) = @_;
  
  unless($encode_flag){
    $location =~ s/([^\w .-~])/'%'.unpack('H2', $1)/eg;
    $location =~ tr/ /+/;
  }
  
  $self->r->headers_out->set('Location' => $location);
  
  $self->stat_code(Apache2::Const::REDIRECT);
  
  goto END_LINE;
}

#------------------------------------------------------------------------
# dump specify value
# * value : debug value
#------------------------------------------------------------------------
sub dump {
  my($self, $value) = @_;
  
  if ($self->stat_header == undef) {
    $self->r->content_type('text/html;charset=utf-8;');
    $self->stat_header(1);
  }
  $self->r->print(Dumpvalue->new()->dumpValue($value));
  
  goto END_LINE;
}

#------------------------------------------------------------------------
# finalizer
# * 
#------------------------------------------------------------------------
sub DESTROY {
  my $self = shift;
  carp "Destroing $self";
}

1;
