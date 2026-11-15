import 'package:flutter_test/flutter_test.dart';
import 'package:nox/assistant/vikunja.dart';
import 'package:nox/assistant/vikunja_client.dart';

void main() {
  final projectsJson = [
    {'id': -1, 'title': 'Favorites'},
    {'id': 1, 'title': 'Maison', 'parent_project_id': 0},
    {'id': 2, 'title': 'Travaux', 'parent_project_id': 1},
    {'id': 3, 'title': 'Claude'},
    {'id': 4, 'title': 'Vieux', 'is_archived': true},
  ];
  final tasksJson = [
    {
      'id': 10,
      'title': 'Peindre',
      'project_id': 2,
      'done': false,
      'due_date': '0001-01-01T00:00:00Z',
    },
    {'id': 11, 'title': 'Poncer', 'project_id': 2, 'done': true},
    {
      'id': 12,
      'title': 'Devis',
      'project_id': 1,
      'done': false,
      'labels': [
        {'title': 'En cours'},
      ],
    },
    {'id': 13, 'title': 'Onglets Nox', 'project_id': 3, 'done': false},
    {'id': 14, 'title': 'Vikunja dans Nox', 'project_id': 3, 'done': false},
    {'id': 15, 'title': 'Fini', 'project_id': 3, 'done': true},
    {'title': 'sans id'},
  ];

  test('projects: pseudo and archived ones left out', () {
    expect(parseProjects(projectsJson).map((p) => p.id), [1, 2, 3]);
  });

  test('tasks: year-1 due date means none, labels read', () {
    final tasks = parseTasks(tasksJson);
    expect(tasks, hasLength(6));
    expect(tasks.first.due, isNull);
    expect(tasks[2].labels, ['En cours']);
  });

  test('kanban view and in-progress buckets', () {
    expect(
      kanbanViewId([
        {'id': 5, 'view_kind': 'list'},
        {'id': 8, 'view_kind': 'kanban'},
      ]),
      8,
    );
    expect(
      kanbanViewId([
        {'id': 5, 'view_kind': 'list'},
      ]),
      isNull,
    );
    expect(
      inProgressTaskIds([
        {
          'title': 'À faire',
          'tasks': [
            {'id': 1},
          ],
        },
        {
          'title': 'En cours',
          'tasks': [
            {'id': 10},
            {'id': 14},
          ],
        },
        {'title': 'Doing', 'tasks': null},
      ]),
      {10, 14},
    );
  });

  test('tracking: in progress, Claude\'s tasks and project progress', () {
    final t = buildTracking(parseProjects(projectsJson), parseTasks(tasksJson), {10, 14});
    expect(t.inProgress.map((x) => x.title), ['Devis', 'Peindre']);
    expect(t.claude!.map((x) => x.title), ['Vikunja dans Nox', 'Onglets Nox']);
    expect(t.inProgressIds, {10, 12, 14});
    expect(t.projects.map((p) => p.path), ['Maison', 'Maison › Travaux']);
    final travaux = t.projects[1];
    expect((travaux.done, travaux.total, travaux.inProgress), (1, 2, 1));
    expect(t.projectNames[2], 'Maison › Travaux');
  });

  test('without a Claude project there is no Claude section', () {
    final t = buildTracking(parseProjects(projectsJson.take(3).toList()), const [], const {});
    expect(t.claude, isNull);
  });

  test('vikunja address', () {
    expect(normalizeVikunjaUrl('vikunja.local:3456'), 'http://vikunja.local:3456');
    expect(normalizeVikunjaUrl('https://v.ex.fr/api/v1/'), 'https://v.ex.fr');
    expect(normalizeVikunjaUrl(''), isNull);
  });
}
