opensprogskole_vala_sources = [
  'main.vala',
  'application.vala',
  'util.vala',
  'models/entity.vala',
  'models/timetable-item.vala',
  'models/grade.vala',
  'models/school.vala',
  'models/user-info-item.vala',
  'models/link-item.vala',
  'models/absence-item.vala',
  'models/absence-summary.vala',
  'models/absence-settings.vala',
  'models/future-absence-item.vala',
  'models/call-in-sick-settings.vala',
  'models/user-info-settings.vala',
  'store/timetable-store.vala',
  'services/connectivity.vala',
  'services/json-cache.vala',
  'services/school-provider.vala',
  'services/schools.vala',
  'services/secret-store.vala',
  'services/ums-client.vala',
  'services/ums-provider.vala',
  'services/session.vala',
  'services/session-controller.vala',
  'services/avatar-cache.vala',
  'views/schedule-view.vala',
  'views/onboarding-view.vala',
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
]

opensprogskole_sources = [
	opensprogskole_vala_sources,
	opensprogskole_resources,
]

opensprogskole_deps = [
  config_dep,
  dependency('gtk4', version: '>= 4.22'),
  dependency('libadwaita-1', version: '>= 1.6'),
  dependency('json-glib-1.0', version: '>= 1.10.0'),
  dependency('libsoup-3.0', version: '>= 3.6.0'),
  dependency('libsecret-1'),
]

opensprogskole_vala_args = [
	'--gresources', opensprogskole_resource_files,
	# libsecret's Vala bindings live outside valac's default vapidir on this
	# system; make sure they are found.
	'--vapidir=/usr/share/vala/vapi',
]

executable('opensprogskole', opensprogskole_sources,
  dependencies: opensprogskole_deps,
  include_directories: config_inc,
        vala_args: opensprogskole_vala_args,
          # Name the GLib log domain so our debug()/warning()/message() calls can
          # be filtered on their own, e.g. `G_MESSAGES_DEBUG=opensprogskole`,
          # without pulling in libsoup/GIO debug spam (which `=all` would).
            c_args: ['-DG_LOG_DOMAIN="opensprogskole"'],
          install: true,
)
