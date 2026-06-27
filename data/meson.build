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
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
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
    'ui/main-view.blp',
    'ui/overview-page.blp',
    'ui/absence-page.blp',
    'ui/grades-page.blp',
    'ui/profile-page.blp',
    'ui/edit-profile-page.blp',
  ),
  output: 'blueprints',
  command: [find_program('blueprint-compiler'), 'batch-compile', '--minify', '@OUTPUT@', '@CURRENT_SOURCE_DIR@', '@INPUT@'],
)

# Compile resources. The .ui files are produced under <builddir>/data/blueprints
# (mirroring the source ui/ layout); sample assets live in the source tree.
opensprogskole_resource_files = files('opensprogskole.gresource.xml')
opensprogskole_resources = gnome.compile_resources('opensprogskole-resources',
  opensprogskole_resource_files,
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
