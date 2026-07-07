# UI-free service core, compiled once as a static library so the unit tests
# in tests/ can link the exact same objects the app uses (Vala sources can't
# be listed across subdirs — meson mislays the generated C files).
opensprogskole_core_deps = [
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gio-2.0'),
  dependency('json-glib-1.0', version: '>= 1.10.0'),
  dependency('libsoup-3.0', version: '>= 3.6.0'),
]

opensprogskole_core = static_library('opensprogskole-core',
  [
    'models/school.vala',
    'services/error-reporter.vala',
    'services/school-config.vala',
    'services/ums-endpoints.vala',
  ],
  dependencies: opensprogskole_core_deps,
)

opensprogskole_vala_sources = [
  'main.vala',
  'application.vala',
  'util.vala',
  'models/entity.vala',
  'models/timetable-item.vala',
  'models/grade.vala',
  'models/user-info-item.vala',
  'models/link-item.vala',
  'models/absence-item.vala',
  'models/absence-summary.vala',
  'models/absence-settings.vala',
  'models/future-absence-item.vala',
  'models/user-info-settings.vala',
  'store/timetable-store.vala',
  'services/connectivity.vala',
  'services/storage.vala',
  'services/school-provider.vala',
  'services/login-method.vala',
  'services/provider-family.vala',
  'services/demo-provider.vala',
  'services/schools.vala',
  'services/secret-store.vala',
  'services/ums-client.vala',
  'services/ums-provider.vala',
  'services/session.vala',
  'services/session-controller.vala',
  'services/avatar-cache.vala',
  'views/schedule-view.vala',
  'views/onboarding-view.vala',
  'views/preferences-dialog.vala',
  'views/school-picker.vala',
  'views/main-view.vala',
  'views/overview-page.vala',
  'views/absence-page.vala',
  'views/links-page.vala',
  'views/grades-page.vala',
  'views/profile-page.vala',
  'views/edit-profile-page.vala',
  'widgets/window.vala',
  'widgets/styles.vala',
  'widgets/loading-state.vala',
  'widgets/chart.vala',
  'widgets/calendar.vala',
  'widgets/calendar-day.vala',
  'widgets/grades.vala',
  'widgets/day-lessons.vala',
  'widgets/agenda.vala',
  'widgets/lesson-dialog.vala',
  'widgets/absence-dialog.vala',
  'widgets/reason-dialog.vala',
  'widgets/error-details-dialog.vala',
  'gvdb-glue.vapi',
  'gvdb-glue.c',
]

opensprogskole_sources = [
	opensprogskole_vala_sources,
	opensprogskole_resources,
]

# GVDB (GVariant database) copylib, pinned meson subproject. Its dependency
# exposes the sources directly, so gvdb compiles straight into our target.
gvdb_dep = dependency('gvdb',
  fallback: ['gvdb', 'gvdb_dep'],
  default_options: ['tests=false', 'build-tools=false'],
)

opensprogskole_deps = [
  config_dep,
  dependency('gtk4', version: '>= 4.22'),
  dependency('libadwaita-1', version: '>= 1.6'),
  dependency('json-glib-1.0', version: '>= 1.10.0'),
  dependency('libsoup-3.0', version: '>= 3.6.0'),
  dependency('libsecret-1'),
  dependency('gioopenssl', required: host_machine.system() == 'android'),
  gvdb_dep,
]

opensprogskole_vala_args = [
	'--gresources', gresource_xml,
	'--vapidir=/usr/share/vala/vapi',
]

executable('opensprogskole', opensprogskole_sources,
  dependencies: opensprogskole_deps,
  link_with: opensprogskole_core,
  include_directories: [config_inc, include_directories('.')],
        vala_args: opensprogskole_vala_args,
           c_args: ['-DG_LOG_DOMAIN="opensprogskole"'],
           install: true,
           android_exe_type: 'application',
)
