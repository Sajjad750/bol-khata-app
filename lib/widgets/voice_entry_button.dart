import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../providers/database_providers.dart';
import '../providers/language_providers.dart';
import '../screens/voice_confirm_screen.dart';
import '../database/customer_search.dart';
import '../services/entry_parser_service.dart';
import '../services/transcription_service.dart';
import '../theme/khata_colors.dart';
import '../utils/user_facing_error.dart';

/// Hold-to-record mic: record → transcribe → parse → confirm screen.
class VoiceEntryButton extends ConsumerStatefulWidget {
  const VoiceEntryButton({
    super.key,
    this.transcriptionService,
    this.entryParserService,
    this.lockedCustomerId,
    this.lockedCustomerName,
    this.compact = false,
    this.showLabel = true,
  });

  final TranscriptionService? transcriptionService;
  final EntryParserService? entryParserService;

  /// When set (customer khata page), skip customer picker and attach entry here.
  final int? lockedCustomerId;
  final String? lockedCustomerName;

  /// Smaller mic for header / bottom-bar layouts (no long caption).
  final bool compact;

  /// When false, only the circular mic is shown (fits bottom action bars).
  final bool showLabel;

  @override
  ConsumerState<VoiceEntryButton> createState() => _VoiceEntryButtonState();
}

enum _VoiceUiState { idle, recording, transcribing, parsing }

class _VoiceEntryButtonState extends ConsumerState<VoiceEntryButton>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  late final TranscriptionService _transcription =
      widget.transcriptionService ?? TranscriptionService();
  late final EntryParserService _parser =
      widget.entryParserService ?? EntryParserService();

  late final AnimationController _pulse;

  _VoiceUiState _state = _VoiceUiState.idle;
  String? _activePath;
  bool _ownsTranscription = true;
  bool _ownsParser = true;

  @override
  void initState() {
    super.initState();
    _ownsTranscription = widget.transcriptionService == null;
    _ownsParser = widget.entryParserService == null;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    unawaited(_recorder.dispose());
    if (_ownsTranscription) _transcription.dispose();
    if (_ownsParser) _parser.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_state != _VoiceUiState.idle) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      await _showError(
        'Microphone permission is required for voice entry.',
        allowRetry: false,
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'khata_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e) {
      if (!mounted) return;
      await _showError('Could not start recording: $e', allowRetry: false);
      return;
    }

    HapticFeedback.mediumImpact();
    _activePath = path;
    _pulse.repeat(reverse: true);
    if (mounted) setState(() => _state = _VoiceUiState.recording);
  }

  Future<void> _stopAndProcess() async {
    if (_state != _VoiceUiState.recording) return;

    _pulse.stop();
    _pulse.value = 0;
    if (mounted) setState(() => _state = _VoiceUiState.transcribing);

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _activePath;
    }
    path ??= _activePath;
    _activePath = null;

    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _state = _VoiceUiState.idle);
      await _showError(
        'No recording captured. Hold the button, speak, then release.',
      );
      return;
    }

    try {
      final language = ref.read(languageControllerProvider).language;
      final text = await _transcription.transcribe(path, language: language);
      if (!mounted) return;
      setState(() => _state = _VoiceUiState.parsing);

      final entry = await _parser.parse(text, language: language);
      final lockedId = widget.lockedCustomerId;
      List<CustomerSearchHit> candidates;
      var ambiguous = false;

      if (lockedId != null) {
        // Customer already chosen on their khata page — no fuzzy match needed.
        final customer = await ref.read(databaseProvider).getCustomer(lockedId);
        if (customer == null) {
          candidates = const [];
        } else {
          final aliases = await ref
              .read(databaseProvider)
              .getAliasesForCustomer(customer.id);
          candidates = [
            CustomerSearchHit(
              customer: customer,
              score: 1,
              matchedOn: customer.name,
              aliases: aliases,
            ),
          ];
        }
      } else {
        final search = await ref
            .read(databaseProvider)
            .searchCustomers(entry.spokenReference);
        candidates = search.matches.take(3).toList();
        ambiguous = search.ambiguous;
      }

      if (!mounted) return;
      setState(() => _state = _VoiceUiState.idle);

      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => VoiceConfirmScreen(
            entry: entry,
            candidates: candidates,
            ambiguousMatch: ambiguous,
            lockedCustomerId: lockedId,
            lockedCustomerName:
                widget.lockedCustomerName ??
                (candidates.isEmpty ? null : candidates.first.name),
          ),
        ),
      );
    } on TranscriptionException catch (e) {
      if (!mounted) return;
      setState(() => _state = _VoiceUiState.idle);
      await _showError(
        userFacingMessage(
          e,
          fallback: 'Could not hear clearly. Try again or enter manually.',
        ),
      );
    } on EntryParseException catch (e) {
      if (!mounted) return;
      setState(() => _state = _VoiceUiState.idle);
      await _showError(
        userFacingMessage(
          e,
          fallback:
              'Could not understand the entry. Try again or enter manually.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _VoiceUiState.idle);
      await _showError(
        userFacingMessage(
          e,
          fallback: 'Something went wrong. Try again or enter manually.',
        ),
      );
    } finally {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _cancelRecording() async {
    if (_state != _VoiceUiState.recording) return;
    _pulse.stop();
    _pulse.value = 0;
    try {
      await _recorder.cancel();
    } catch (_) {}
    _activePath = null;
    if (mounted) setState(() => _state = _VoiceUiState.idle);
  }

  Future<void> _openManualEntry() async {
    final id = widget.lockedCustomerId;
    final name = widget.lockedCustomerName;
    if (id == null || name == null || name.isEmpty) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VoiceConfirmScreen.manualForCustomer(
          customerId: id,
          customerName: name,
        ),
      ),
    );
  }

  Future<void> _showError(String message, {bool allowRetry = true}) async {
    final useManual = widget.lockedCustomerId != null;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voice entry failed'),
        content: Text(message),
        actions: [
          if (useManual)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'manual'),
              child: const Text('Enter manually'),
            ),
          if (allowRetry)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: const Text('Try again'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(ctx, useManual ? 'manual' : 'ok'),
              child: Text(useManual ? 'Enter manually' : 'OK'),
            ),
          if (!useManual && allowRetry)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'ok'),
              child: const Text('OK'),
            ),
        ],
      ),
    );
    if (result == 'manual' && mounted) {
      await _openManualEntry();
    }
  }

  String get _label {
    final s = ref.read(appStringsProvider);
    if (widget.compact) {
      switch (_state) {
        case _VoiceUiState.idle:
          return s.speak;
        case _VoiceUiState.recording:
          return s.listening;
        case _VoiceUiState.transcribing:
        case _VoiceUiState.parsing:
          return s.wait;
      }
    }
    switch (_state) {
      case _VoiceUiState.idle:
        final name = widget.lockedCustomerName;
        return name != null && name.isNotEmpty
            ? s.holdToSpeakNamed(name)
            : s.holdToSpeakFor;
      case _VoiceUiState.recording:
        return s.listening;
      case _VoiceUiState.transcribing:
        return s.wait;
      case _VoiceUiState.parsing:
        return s.wait;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = _state == _VoiceUiState.recording;
    final isBusy =
        _state == _VoiceUiState.transcribing || _state == _VoiceUiState.parsing;
    final size = widget.compact ? 56.0 : 88.0;
    final iconSize = widget.compact ? 26.0 : 40.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: widget.compact
              ? 'Hold to speak for ${widget.lockedCustomerName ?? 'customer'}'
              : _label,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: isBusy
                ? null
                : (_) {
                    unawaited(_startRecording());
                  },
            onPointerUp: isBusy
                ? null
                : (_) {
                    unawaited(_stopAndProcess());
                  },
            onPointerCancel: isBusy
                ? null
                : (_) {
                    unawaited(_cancelRecording());
                  },
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final scale = isRecording ? 1.0 + (_pulse.value * 0.12) : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: Material(
                color: isRecording
                    ? const Color(0xFFB91C1C)
                    : KhataColors.primaryGreen,
                shape: const CircleBorder(),
                elevation: isRecording ? 6 : 2,
                shadowColor: KhataColors.primaryGreen.withValues(alpha: 0.35),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Center(
                    child: isBusy
                        ? SizedBox(
                            width: widget.compact ? 22 : 32,
                            height: widget.compact ? 22 : 32,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isRecording ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                            size: iconSize,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.showLabel) ...[
          SizedBox(height: widget.compact ? 6 : 8),
          Text(
            _label,
            textAlign: TextAlign.center,
            maxLines: widget.compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isRecording
                  ? const Color(0xFFB91C1C)
                  : Colors.grey.shade700,
              fontWeight: FontWeight.w700,
              fontSize: widget.compact ? 12 : 15,
            ),
          ),
        ],
      ],
    );
  }
}
