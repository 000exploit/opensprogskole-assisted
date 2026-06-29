desktop_file = i18n.merge_file(
        input: 'moe.ekusu.sprogskole.desktop.in',
       output: 'moe.ekusu.sprogskole.desktop',
         type: 'desktop',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'applications'
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

appstream_file = i18n.merge_file(
        input: 'moe.ekusu.sprogskole.metainfo.xml.in',
       output: 'moe.ekusu.sprogskole.metainfo.xml',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'metainfo'
)

appstreamcli = find_program('appstreamcli', required: false, disabler: true)
test('Validate appstream file', appstreamcli,
     args: ['validate', '--no-net', '--explain', appstream_file])

install_data('moe.ekusu.sprogskole.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
  install_tag: 'runtime',
)

# Recompile the schema into the build dir whenever the .xml changes, so an
# uninstalled run (meson devenv) never sees a stale gschemas.compiled.
gnome = import('gnome')
gnome.compile_schemas(
  depend_files: files('moe.ekusu.sprogskole.gschema.xml'),
)

compile_schemas = find_program('glib-compile-schemas', required: false, disabler: true)
test('Validate schema file',
     compile_schemas,
     args: ['--strict', '--dry-run', meson.current_source_dir()])

# Compile blueprints into a dedicated subdirectory rather than '.', so the
# blueprint compiler can't clobber the configure-time files in this build dir
# (.service / .desktop / .metainfo). See the gresource source_dir below.
blueprints = custom_target('blueprints',
  input: files(
    'ui/window.blp',
    'ui/shortcuts-dialog.blp',
    'ui/loading-state.blp',
    'ui/chart.blp',
    'ui/calendar.blp',
    'ui/calendar-day.blp',
    'ui/grades.blp',
    'ui/day-lessons.blp',
    'ui/agenda.blp',
    'ui/lesson-dialog.blp',
    'ui/absence-dialog.blp',
    'ui/reason-dialog.blp',
    'ui/schedule-view.blp',
    'ui/onboarding-view.blp',
    'ui/school-picker.blp',
    'ui/main-view.blp',
    'ui/overview-page.blp',
    'ui/absence-page.blp',
    'ui/links-page.blp',
    'ui/grades-page.blp',
    'ui/profile-page.blp',
    'ui/edit-profile-page.blp',
  ),
  output: 'blueprints',
  command: [find_program('blueprint-compiler'), 'batch-compile', '--minify', '@OUTPUT@', '@CURRENT_SOURCE_DIR@', '@INPUT@'],
)

fs = import('fs')
android_icon_files = files(
  'icons/scalable/actions/accessories-dictionary-symbolic.svg',
  'icons/scalable/actions/adw-external-link-symbolic.svg',
  'icons/scalable/actions/application-rss+xml-symbolic.svg',
  'icons/scalable/actions/applications-games-symbolic.svg',
  'icons/scalable/actions/appointment-soon-symbolic.svg',
  'icons/scalable/actions/avatar-default-symbolic.svg',
  'icons/scalable/actions/camera-photo-symbolic.svg',
  'icons/scalable/actions/dialog-information-symbolic.svg',
  'icons/scalable/actions/dialog-password-symbolic.svg',
  'icons/scalable/actions/dialog-warning-symbolic.svg',
  'icons/scalable/actions/document-edit-symbolic.svg',
  'icons/scalable/actions/edit-copy-symbolic.svg',
  'icons/scalable/actions/face-sad-symbolic.svg',
  'icons/scalable/actions/folder-documents-symbolic.svg',
  'icons/scalable/actions/go-next-symbolic.svg',
  'icons/scalable/actions/list-add-symbolic.svg',
  'icons/scalable/actions/network-offline-symbolic.svg',
  'icons/scalable/actions/network-wireless-symbolic.svg',
  'icons/scalable/actions/network-workgroup-symbolic.svg',
  'icons/scalable/actions/object-select-symbolic.svg',
  'icons/scalable/actions/open-menu-symbolic.svg',
  'icons/scalable/actions/pan-end-symbolic.svg',
  'icons/scalable/actions/pan-start-symbolic.svg',
  'icons/scalable/actions/starred-symbolic.svg',
  'icons/scalable/actions/system-search-symbolic.svg',
  'icons/scalable/actions/user-trash-symbolic.svg',
  'icons/scalable/actions/view-grid-symbolic.svg',
  'icons/scalable/actions/view-more-horizontal-symbolic.svg',
  'icons/scalable/actions/view-refresh-symbolic.svg',
  'icons/scalable/actions/web-browser-symbolic.svg',
  'icons/scalable/actions/x-office-calendar-symbolic.svg',
)
android_icons_xml = ''
if host_machine.system() == 'android'
  foreach icon : android_icon_files
    android_icons_xml += '<file preprocess="xml-stripblanks">icons/scalable/actions/' + fs.name(icon) + '</file>\n'
  endforeach
endif

gresource_xml = configure_file(
  input: 'opensprogskole.gresource.xml.in',
  output: 'opensprogskole.gresource.xml',
  configuration: { 'ANDROID_ICONS': android_icons_xml },
)

# Compile resources. The .ui files are produced under <builddir>/data/blueprints
# (mirroring the source ui/ layout); sample assets live in the source tree.
opensprogskole_resources = gnome.compile_resources('opensprogskole-resources',
  gresource_xml,
  source_dir: [meson.current_build_dir() / 'blueprints', meson.current_source_dir()],
  dependencies: blueprints,
  c_name: 'opensprogskole',
  install_dir: get_option('datadir') / meson.project_name(),
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'moe.ekusu.sprogskole.service.in',
  output: 'moe.ekusu.sprogskole.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

subdir('icons')
