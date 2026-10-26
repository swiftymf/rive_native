import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:rive_native/rive_native.dart' as rive;
import 'package:rive_native/semantics.dart';

/// A [rive.StateMachinePainter] variant whose per-frame advance can be paused
/// and manually stepped, and which emits every non-empty [SemanticsDiff] to a
/// listener before applying it to the internal [SemanticTreeModel].
///
/// Used by [SemanticDebugger]; exposed publicly so custom UIs can build on the
/// same painter.
@experimental
@internal
base class SemanticDebugPainter extends rive.StateMachinePainter {
  SemanticDebugPainter({
    super.stateMachineName,
    super.withStateMachine,
    super.fit,
    super.alignment,
  });

  /// Set true to stop the ticker-driven advance. [stepOnce] still works.
  ///
  /// Intentionally does not call [notifyListeners] on change — the painter's
  /// notification channel is shared with render-pipeline signals, and firing
  /// it outside a paint/advance would cascade rebuilds during widget build.
  /// UIs that need to react to the toggle should drive it from their own
  /// state.
  bool paused = false;

  /// Called with each non-empty diff consumed during [advance]. The diff is
  /// also applied to [rive.RiveSemanticsMixin.semanticTree] as usual.
  void Function(SemanticsDiff diff)? onDiff;

  /// Advance exactly once by [elapsedSeconds] regardless of [paused]. Returns
  /// true if the state machine reported work done.
  bool stepOnce([double elapsedSeconds = 1 / 60]) {
    final advanced = stateMachine?.advanceAndApply(elapsedSeconds) ?? false;
    updateSemantics();
    scheduleRepaint();
    return advanced;
  }

  @override
  bool advance(double elapsedSeconds) {
    if (paused) return false;
    return super.advance(elapsedSeconds);
  }

  // Captures each non-empty diff before it's applied to the tree model, so
  // the debugger log shows exactly what the native runtime emitted.
  @override
  void updateSemantics() {
    final tree = semanticTree;
    final sm = semanticsStateMachine;
    if (tree == null || sm == null) return;
    final diff = sm.drainSemanticsDiff();
    if (diff.isEmpty) return;
    onDiff?.call(diff);
    tree.applyDiff(diff);
  }
}

/// One entry in the debugger log — a captured [SemanticsDiff] with the time
/// it was emitted and a cached summary.
@experimental
@internal
@immutable
class SemanticsDiffLogEntry {
  SemanticsDiffLogEntry({required this.time, required this.diff})
      : summary = _summarize(diff);

  final DateTime time;
  final SemanticsDiff diff;
  final String summary;

  static String _summarize(SemanticsDiff d) {
    final parts = <String>[];
    if (d.added.isNotEmpty) parts.add('+${d.added.length}');
    if (d.removed.isNotEmpty) parts.add('-${d.removed.length}');
    if (d.moved.isNotEmpty) parts.add('~${d.moved.length}');
    if (d.updatedSemantic.isNotEmpty) {
      parts.add('sem:${d.updatedSemantic.length}');
    }
    if (d.updatedGeometry.isNotEmpty) {
      parts.add('geo:${d.updatedGeometry.length}');
    }
    if (d.childrenUpdated.isNotEmpty) {
      parts.add('children:${d.childrenUpdated.length}');
    }
    return parts.isEmpty ? 'empty' : parts.join(' ');
  }
}

/// Ring-buffer log of captured [SemanticsDiff]s. Notifies listeners when a
/// new entry is appended or the log is cleared.
@experimental
@internal
class SemanticsDiffLog extends ChangeNotifier {
  SemanticsDiffLog({this.maxEntries = 200});

  final int maxEntries;
  final List<SemanticsDiffLogEntry> _entries = [];

  List<SemanticsDiffLogEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;

  void append(SemanticsDiff diff) {
    _entries.add(SemanticsDiffLogEntry(time: DateTime.now(), diff: diff));
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

/// A debugger widget that renders a .riv artboard alongside play/pause/step
/// controls and a live log of every non-empty [SemanticsDiff] emitted by the
/// state machine.
///
/// Load by asset path. Supply an [artboardName] / [stateMachineName] to pick
/// a specific target, or omit both for the defaults.
///
/// ```dart
/// SemanticDebugger(
///   asset: 'assets/simpsons.riv',
///   factory: Factory.rive,   // or your factory of choice
/// )
/// ```
@experimental
@internal
class SemanticDebugger extends StatefulWidget {
  const SemanticDebugger({
    required this.asset,
    required this.factory,
    this.artboardName,
    this.stateMachineName,
    this.fit = rive.Fit.contain,
    this.alignment = Alignment.center,
    this.maxLogEntries = 200,
    this.assetLoader,
    this.autoBind = true,
    super.key,
  });

  final String asset;
  final rive.Factory factory;
  final String? artboardName;
  final String? stateMachineName;
  final rive.Fit fit;
  final Alignment alignment;
  final int maxLogEntries;
  final rive.AssetLoaderCallback? assetLoader;

  /// When true (default), binds the artboard's default view model instance
  /// to the state machine once it's resolved. Mirrors the behaviour of the
  /// example app's `RivePlayer`. Set false to inspect a file whose semantics
  /// are driven entirely by the state machine / direct input.
  final bool autoBind;

  @override
  State<SemanticDebugger> createState() => _SemanticDebuggerState();
}

class _SemanticDebuggerState extends State<SemanticDebugger> {
  rive.File? _file;
  rive.Artboard? _artboard;
  SemanticDebugPainter? _painter;
  late final SemanticsDiffLog _log =
      SemanticsDiffLog(maxEntries: widget.maxLogEntries);
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SemanticDebugger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset ||
        oldWidget.factory != widget.factory ||
        oldWidget.artboardName != widget.artboardName ||
        oldWidget.stateMachineName != widget.stateMachineName) {
      _disposeFileResources();
      _log.clear();
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await rootBundle.load(widget.asset);
      final file = await rive.File.decode(
        bytes.buffer.asUint8List(),
        riveFactory: widget.factory,
        assetLoader: widget.assetLoader,
      );
      if (file == null) {
        setState(() => _loadError = 'File.decode returned null');
        return;
      }

      final artboard = widget.artboardName != null
          ? file.artboard(widget.artboardName!)
          : file.defaultArtboard();
      if (artboard == null) {
        file.dispose();
        setState(
            () => _loadError = 'Artboard not found: ${widget.artboardName}');
        return;
      }

      final painter = SemanticDebugPainter(
        stateMachineName: widget.stateMachineName,
        fit: widget.fit,
        alignment: widget.alignment,
        withStateMachine: widget.autoBind
            ? (stateMachine) => _tryAutoBind(file, artboard, stateMachine)
            : null,
      );
      painter.semanticsEnabled = true;
      painter.onDiff = _log.append;

      if (!mounted) {
        painter.dispose();
        artboard.dispose();
        file.dispose();
        return;
      }

      setState(() {
        _file = file;
        _artboard = artboard;
        _painter = painter;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  // Binds the artboard's default view model instance to the state machine,
  // if one exists. No-op when the file has no default view model (e.g.
  // state-machine-only files) — the debugger still works without a binding.
  void _tryAutoBind(
    rive.File file,
    rive.Artboard artboard,
    rive.StateMachine stateMachine,
  ) {
    final vm = file.defaultArtboardViewModel(artboard);
    if (vm == null) return;
    final vmi = vm.createDefaultInstance();
    if (vmi == null) return;
    stateMachine.bindViewModelInstance(vmi);
  }

  void _disposeFileResources() {
    _painter?.dispose();
    _artboard?.dispose();
    _file?.dispose();
    _painter = null;
    _artboard = null;
    _file = null;
  }

  @override
  void dispose() {
    _disposeFileResources();
    _log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Failed to load ${widget.asset}\n$_loadError'),
        ),
      );
    }
    final artboard = _artboard;
    final painter = _painter;
    if (artboard == null || painter == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Only the Rive render area contributes to Flutter's semantic tree: the
    // debugger chrome (toolbar, dividers, log) is excluded so screen readers
    // aren't announcing debugger state, and the artboard is wrapped in
    // RiveSemanticsWidget so its own semantic nodes do project through.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: _DebuggerToolbar(
            paused: painter.paused,
            onTogglePaused: _togglePaused,
            onStep: painter.stepOnce,
            log: _log,
          ),
        ),
        const ExcludeSemantics(child: Divider(height: 1)),
        Expanded(
          flex: 3,
          child: rive.RiveSemanticsWidget(
            artboard: artboard,
            painter: painter,
            child: rive.RiveArtboardWidget(
              artboard: artboard,
              painter: painter,
            ),
          ),
        ),
        const ExcludeSemantics(child: Divider(height: 1)),
        Expanded(
          flex: 2,
          child: ExcludeSemantics(child: _DiffLogPanel(log: _log)),
        ),
      ],
    );
  }

  void _togglePaused() {
    final painter = _painter;
    if (painter == null) return;
    setState(() => painter.paused = !painter.paused);
  }
}

class _DebuggerToolbar extends StatelessWidget {
  const _DebuggerToolbar({
    required this.paused,
    required this.onTogglePaused,
    required this.onStep,
    required this.log,
  });

  final bool paused;
  final VoidCallback onTogglePaused;
  final VoidCallback onStep;
  final SemanticsDiffLog log;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: paused ? 'Play' : 'Pause',
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            onPressed: onTogglePaused,
          ),
          IconButton(
            tooltip: 'Step one frame (~16ms)',
            icon: const Icon(Icons.skip_next),
            onPressed: onStep,
          ),
          const SizedBox(width: 8),
          Text(
            paused ? 'paused' : 'running',
            style: TextStyle(
              fontSize: 12,
              color: paused ? Colors.amber : Colors.greenAccent,
            ),
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: log,
            builder: (context, _) => Text(
              '${log.length} diff${log.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete_outline),
            onPressed: log.clear,
          ),
        ],
      ),
    );
  }
}

class _DiffLogPanel extends StatefulWidget {
  const _DiffLogPanel({required this.log});

  final SemanticsDiffLog log;

  @override
  State<_DiffLogPanel> createState() => _DiffLogPanelState();
}

class _DiffLogPanelState extends State<_DiffLogPanel> {
  final _scroll = ScrollController();
  int _lastLength = 0;

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    widget.log.removeListener(_onLogChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (!mounted) return;
    final length = widget.log.length;
    if (length > _lastLength && _scroll.hasClients) {
      // Auto-scroll to bottom when new entries arrive.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      });
    }
    _lastLength = length;
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListenableBuilder(
        listenable: widget.log,
        builder: (context, _) {
          final entries = widget.log.entries;
          if (entries.isEmpty) {
            return const Center(
              child: Text(
                'No diffs yet — advance the state machine to see semantic '
                'changes here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return ListView.builder(
            controller: _scroll,
            itemCount: entries.length,
            itemBuilder: (context, index) =>
                _DiffLogTile(entry: entries[entries.length - 1 - index]),
          );
        },
      ),
    );
  }
}

class _DiffLogTile extends StatelessWidget {
  const _DiffLogTile({required this.entry});

  final SemanticsDiffLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = entry.time;
    final timestamp = '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
    final diff = entry.diff;
    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Row(
        children: [
          Text(
            timestamp,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'frame ${diff.frameNumber} · tree v${diff.treeVersion}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.summary,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
      children: [
        _DiffSection(
          title: 'added',
          empty: diff.added.isEmpty,
          body: () => diff.added.map(_nodeLine).toList(),
        ),
        _DiffSection(
          title: 'removed',
          empty: diff.removed.isEmpty,
          body: () => diff.removed.map((id) => 'id=$id').toList(),
        ),
        _DiffSection(
          title: 'moved',
          empty: diff.moved.isEmpty,
          body: () => diff.moved.map(_nodeLine).toList(),
        ),
        _DiffSection(
          title: 'updatedSemantic',
          empty: diff.updatedSemantic.isEmpty,
          body: () => diff.updatedSemantic.map(_nodeDetail).toList(),
        ),
        _DiffSection(
          title: 'updatedGeometry',
          empty: diff.updatedGeometry.isEmpty,
          body: () => diff.updatedGeometry
              .map((b) =>
                  'id=${b.id} [${_f(b.minX)},${_f(b.minY)}→${_f(b.maxX)},${_f(b.maxY)}]')
              .toList(),
        ),
        _DiffSection(
          title: 'childrenUpdated',
          empty: diff.childrenUpdated.isEmpty,
          body: () => diff.childrenUpdated
              .map((c) => 'parent=${c.parentId} → [${c.childIds.join(', ')}]')
              .toList(),
        ),
      ],
    );
  }

  static String _nodeLine(SemanticsDiffNode n) {
    final label = n.label.isEmpty ? '<no label>' : '"${n.label}"';
    final traits = _decodeFlags(n.traitFlags, _traitNames);
    final states = _decodeFlags(n.stateFlags, _stateNames);
    final buf = StringBuffer(
        'id=${n.id} ${n.role.name} $label parent=${n.parentId}');
    if (traits.isNotEmpty) buf.write(' traits=[$traits]');
    if (states.isNotEmpty) buf.write(' states=[$states]');
    return buf.toString();
  }

  // Full dump of every SemanticsDiffNode field. Used for updatedSemantic so
  // it's obvious *what* changed (traits/states decoded by name, strings
  // quoted so empty values are visible).
  static String _nodeDetail(SemanticsDiffNode n) {
    final buf = StringBuffer()
      ..write('id=${n.id} role=${n.role.name} '
          'parent=${n.parentId} sibling=${n.siblingIndex}')
      ..write('\n  label=${_quote(n.label)}')
      ..write('\n  value=${_quote(n.value)}')
      ..write('\n  hint=${_quote(n.hint)}')
      ..write('\n  traits=[${_decodeFlags(n.traitFlags, _traitNames)}]'
          '  traitFlags=0x${n.traitFlags.toRadixString(16)}')
      ..write('\n  states=[${_decodeFlags(n.stateFlags, _stateNames)}]'
          '  stateFlags=0x${n.stateFlags.toRadixString(16)}')
      ..write('\n  headingLevel=${n.headingLevel}')
      ..write('\n  bounds=[${_f(n.minX)},${_f(n.minY)}'
          ' → ${_f(n.maxX)},${_f(n.maxY)}]');
    return buf.toString();
  }

  static String _quote(String s) => s.isEmpty ? '""' : '"$s"';

  static String _decodeFlags(int flags, Map<int, String> names) {
    if (flags == 0) return '';
    final out = <String>[];
    names.forEach((bit, name) {
      if (flags & bit != 0) out.add(name);
    });
    return out.join(', ');
  }

  static const Map<int, String> _traitNames = {
    SemanticTrait.expandable: 'expandable',
    SemanticTrait.selectable: 'selectable',
    SemanticTrait.checkable: 'checkable',
    SemanticTrait.toggleable: 'toggleable',
    SemanticTrait.requirable: 'requirable',
    SemanticTrait.enablable: 'enablable',
    SemanticTrait.focusable: 'focusable',
  };

  static const Map<int, String> _stateNames = {
    SemanticState.expanded: 'expanded',
    SemanticState.selected: 'selected',
    SemanticState.checked: 'checked',
    SemanticState.mixed: 'mixed',
    SemanticState.toggled: 'toggled',
    SemanticState.required: 'required',
    SemanticState.disabled: 'disabled',
    SemanticState.focused: 'focused',
    SemanticState.hidden: 'hidden',
    SemanticState.liveRegion: 'liveRegion',
    SemanticState.readOnly: 'readOnly',
    SemanticState.modal: 'modal',
    SemanticState.obscured: 'obscured',
    SemanticState.multiline: 'multiline',
  };

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _f(double v) => v.toStringAsFixed(1);
}

class _DiffSection extends StatelessWidget {
  const _DiffSection({
    required this.title,
    required this.empty,
    required this.body,
  });

  final String title;
  final bool empty;
  final List<String> Function() body;

  @override
  Widget build(BuildContext context) {
    if (empty) return const SizedBox.shrink();
    final lines = body();
    // Cap the number of rendered lines so a huge diff doesn't wreck the
    // widget tree; we still expose the full count in the header.
    const maxLines = 50;
    final truncated = lines.length > maxLines;
    final shown =
        truncated ? lines.sublist(0, math.min(maxLines, lines.length)) : lines;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${lines.length})',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.amber,
            ),
          ),
          for (final line in shown)
            Text(
              line,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          if (truncated)
            Text(
              '… ${lines.length - maxLines} more',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
