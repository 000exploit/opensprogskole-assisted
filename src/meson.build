opensprogskole_vala_sources = [
  'main.vala',
  'application.vala',
  'models/entity.vala',
  'models/timetable-item.vala',
  'models/grade.vala',
  'models/school.vala',
  'models/user-info-item.vala',
  'models/link-item.vala',
  'models/absence-item.vala',
  'models/absence-summary.vala',
  'store/timetable-store.vala',
  'services/school-provider.vala',
  'services/schools.vala',
  'services/secret-store.vala',
  'services/ums-client.vala',
  'services/ums-provider.vala',
  'services/session.vala',
  'views/schedule-view.vala',
  'views/onboarding-view.vala',
  'views/main-view.vala',
  'views/overview-page.vala',
  'views/absence-page.vala',
  'views/profile-page.vala',
  'widgets/window.vala',
  'widgets/styles.vala',
  'widgets/chart.vala',
  'widgets/calendar.vala',
  'widgets/calendar-day.vala',
  'widgets/grades.vala',
  'widgets/day-lessons.vala',
  'widgets/agenda.vala',
  'widgets/lesson-dialog.vala',
]

opensprogskole_sources = [
	opensprogskole_vala_sources,
	opensprogskole_resources,
]

opensprogskole_deps = [
  config_dep,
  dependency('gtk4'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
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
          install: true,
)
