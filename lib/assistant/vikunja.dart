// Project tracking read from Vikunja (self-hosted to-do and project app).
//
// Pure Dart: parsing of Vikunja's API answers, so it can be tested without
// a network.

/// A task is "in progress" when it sits in a Kanban bucket with such a
/// title, or carries a label with such a title.
final _inProgress = RegExp(r'en cours|in progress|doing|wip', caseSensitive: false);

bool isInProgressTitle(String title) => _inProgress.hasMatch(title);

/// Name of the project where Claude keeps the tasks it works on.
const kClaudeProject = 'claude';

class VkProject {
  const VkProject({required this.id, required this.title, this.parentId = 0});

  final int id;
  final String title;
  final int parentId;
}

class VkTask {
  const VkTask({
    required this.id,
    required this.title,
    required this.projectId,
    required this.done,
    this.due,
    this.priority = 0,
    this.labels = const [],
  });

  final int id;
  final String title;
  final int projectId;
  final bool done;

  /// Local time, or null when the task has no due date.
  final DateTime? due;
  final int priority;
  final List<String> labels;
}

/// Progress of one project.
class ProjectProgress {
  const ProjectProgress({
    required this.project,
    required this.path,
    required this.done,
    required this.total,
    required this.inProgress,
  });

  final VkProject project;

  /// "Maison › Travaux" for a sub-project.
  final String path;
  final int done;
  final int total;
  final int inProgress;

  double get ratio => total == 0 ? 0 : done / total;
}

/// Everything shown in the "Suivi" tab.
class Tracking {
  const Tracking({
    this.inProgress = const [],
    this.claude,
    this.projects = const [],
    this.projectNames = const {},
    this.inProgressIds = const {},
  });

  /// Open tasks marked in progress, all projects except Claude's.
  final List<VkTask> inProgress;

  /// Open tasks of Claude's project (in progress first), or null when
  /// there is no such project.
  final List<VkTask>? claude;

  /// Ids of the open tasks marked in progress.
  final Set<int> inProgressIds;

  final List<ProjectProgress> projects;

  /// Project id → path, to show where a task comes from.
  final Map<int, String> projectNames;
}

String? _string(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

/// Reads `GET /projects`: real, non-archived projects (Vikunja adds
/// pseudo-projects such as "Favorites" with a negative id).
List<VkProject> parseProjects(Object? json) {
  final projects = <VkProject>[];
  if (json is! List) return projects;
  for (final p in json) {
    if (p is! Map) continue;
    final id = p['id'];
    final title = _string(p['title']);
    if (id is! int || id <= 0 || title == null || p['is_archived'] == true) continue;
    final parent = p['parent_project_id'];
    projects.add(VkProject(id: id, title: title, parentId: parent is int ? parent : 0));
  }
  return projects;
}

/// Vikunja writes "no due date" as year 1.
DateTime? _date(Object? v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v);
  if (d == null || d.year <= 1970) return null;
  return d.toLocal();
}

VkTask? _task(Object? t) {
  if (t is! Map) return null;
  final id = t['id'];
  final title = _string(t['title']);
  final project = t['project_id'];
  if (id is! int || title == null) return null;
  final labels = t['labels'];
  final priority = t['priority'];
  return VkTask(
    id: id,
    title: title,
    projectId: project is int ? project : 0,
    done: t['done'] == true,
    due: _date(t['due_date']),
    priority: priority is int ? priority : 0,
    labels: [
      if (labels is List)
        for (final l in labels)
          if (l is Map) ?_string(l['title']),
    ],
  );
}

/// Reads a list of tasks (`GET /tasks`).
List<VkTask> parseTasks(Object? json) => [
  if (json is List)
    for (final t in json) ?_task(t),
];

/// Reads `GET /projects/{id}/views`: the id of the Kanban view, if any.
int? kanbanViewId(Object? json) {
  if (json is! List) return null;
  for (final v in json) {
    if (v is! Map) continue;
    final kind = v['view_kind'];
    final id = v['id'];
    if ((kind == 'kanban' || kind == 3) && id is int) return id;
  }
  return null;
}

/// Reads the buckets of a Kanban view (or the old `GET /projects/{id}/buckets`):
/// ids of the tasks in an "in progress" bucket.
Set<int> inProgressTaskIds(Object? buckets) {
  final ids = <int>{};
  if (buckets is! List) return ids;
  for (final b in buckets) {
    if (b is! Map) continue;
    final title = _string(b['title']);
    if (title == null || !isInProgressTitle(title)) continue;
    final tasks = b['tasks'];
    if (tasks is! List) continue;
    for (final t in tasks) {
      if (t is Map && t['id'] is int) ids.add(t['id'] as int);
    }
  }
  return ids;
}

/// Most urgent first: due date, then priority, then title.
int compareTasks(VkTask a, VkTask b) {
  final ad = a.due, bd = b.due;
  if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
  if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
  if (a.priority != b.priority) return b.priority.compareTo(a.priority);
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Puts projects, tasks and in-progress marks together.
Tracking buildTracking(List<VkProject> projects, List<VkTask> tasks, Set<int> inProgressIds) {
  final byId = {for (final p in projects) p.id: p};
  String path(VkProject p) {
    final parts = <String>[p.title];
    var parent = byId[p.parentId];
    // Guard against a loop in broken data.
    for (var i = 0; parent != null && i < 10; i++) {
      parts.insert(0, parent.title);
      parent = byId[parent.parentId];
    }
    return parts.join(' › ');
  }

  bool started(VkTask t) =>
      !t.done && (inProgressIds.contains(t.id) || t.labels.any(isInProgressTitle));

  final claudeProject = [
    for (final p in projects)
      if (p.title.toLowerCase() == kClaudeProject) p.id,
  ].firstOrNull;

  final progress = <ProjectProgress>[];
  for (final p in projects) {
    final mine = [
      for (final t in tasks)
        if (t.projectId == p.id) t,
    ];
    progress.add(
      ProjectProgress(
        project: p,
        path: path(p),
        done: mine.where((t) => t.done).length,
        total: mine.length,
        inProgress: mine.where(started).length,
      ),
    );
  }
  progress.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

  final inProgress = [
    for (final t in tasks)
      if (started(t) && t.projectId != claudeProject && byId.containsKey(t.projectId)) t,
  ]..sort(compareTasks);

  List<VkTask>? claude;
  if (claudeProject != null) {
    final open = [
      for (final t in tasks)
        if (t.projectId == claudeProject && !t.done) t,
    ];
    claude = [
      ...[
        for (final t in open)
          if (started(t)) t,
      ]..sort(compareTasks),
      ...[
        for (final t in open)
          if (!started(t)) t,
      ]..sort(compareTasks),
    ];
  }

  return Tracking(
    inProgress: inProgress,
    claude: claude,
    projects: [
      for (final p in progress)
        if (p.project.id != claudeProject) p,
    ],
    projectNames: {for (final p in progress) p.project.id: p.path},
    inProgressIds: {
      for (final t in tasks)
        if (started(t)) t.id,
    },
  );
}
