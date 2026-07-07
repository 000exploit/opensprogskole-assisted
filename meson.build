project('opensprogskole', ['c', 'vala'],
          version: '0.9.9',
    meson_version: '>= 1.9.0',
  default_options: [ 'warning_level=2', 'werror=false', ],
)

i18n = import('i18n')
gnome = import('gnome')
valac = meson.get_compiler('vala')


srcdir = meson.project_source_root() / 'src'

config_h = configuration_data()
config_h.set_quoted('PACKAGE_VERSION', meson.project_version ())
config_h.set_quoted('GETTEXT_PACKAGE', 'opensprogskole')
config_h.set_quoted('APP_ID', 'moe.ekusu.sprogskole')
config_h.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
configure_file(output: 'config.h', configuration: config_h)

config_dep = valac.find_library ('config', dirs: srcdir)
config_inc = include_directories('.')

# The whole section is taken from GeopJr/Tuba #
if host_machine.system() == 'android'
  add_project_arguments(['--define=ANDROID'], language: 'vala')

    add_project_arguments([
    '--pkg=libadwaita-1',
    '--pkg=gtk4',
    '--pkg=libsecret-1',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=glib-2.0'
  ], language: 'vala')

  subproject('glib-networking', default_options: ['default_library=static'])
  subproject('adwaita-fonts')
endif

add_project_arguments('-DGETTEXT_PACKAGE="' + meson.project_name () + '"', language: 'c')

subdir('data')
subdir('src')
subdir('po')
# Unit tests are host tools — pointless inside an APK.
if host_machine.system() != 'android'
  subdir('tests')
endif

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: host_machine.system() != 'android',
  update_desktop_database: true,
)
