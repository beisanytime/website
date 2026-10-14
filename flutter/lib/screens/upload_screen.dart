import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../app_scope.dart';
import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../services/shiur_uploader.dart';
import '../services/video_thumbnails.dart';
import '../state/app_state.dart';
import '../state/toast_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/forui_kit.dart';

/// Publishes a shiur to R2 through the worker's chunked multipart flow.
///
/// Every blocker is named on screen — the native app used to show a form that
/// could not succeed, which read as "upload doesn't work".
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _rabbi = TextEditingController();
  final TextEditingController _date = TextEditingController();

  UploadSelection? _selection;
  Uint8List? _thumbnail;
  double _durationSeconds = 0;

  bool _isPreparing = false;
  bool _isUploading = false;
  double _progress = 0;
  String _status = '';
  String? _error;

  static const List<String> _rabbis = <String>[
    'Rabbi Hartman',
    'Rabbi Rosenfeld',
    'Rabbi Golker',
    'guests',
    'time4mishna',
  ];

  @override
  void initState() {
    super.initState();
    _date.text = _todayIso();
  }

  @override
  void dispose() {
    _title.dispose();
    _rabbi.dispose();
    _date.dispose();
    super.dispose();
  }

  static String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  // MARK: - Picking

  Future<void> _pickFromLibrary() async {
    final picker = ImagePicker();
    try {
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) {
        return;
      }
      await _adoptSelection(picked.path, picked.name, isVideo: true);
    } on Exception catch (error) {
      _fail('Could not open the photo library ($error)');
    }
  }

  Future<void> _pickFromFiles() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a video or audio shiur',
        type: FileType.custom,
        allowedExtensions: const <String>[
          'mp4',
          'mov',
          'm4v',
          'mp3',
          'm4a',
          'wav',
          'aac',
        ],
      );
      final path = file?.path;
      if (path == null) {
        return;
      }
      await _adoptSelection(
        path,
        file!.name,
        isVideo: isVideoFileName(file.name),
      );
    } on Exception catch (error) {
      _fail('Could not open the file picker ($error)');
    }
  }

  /// Copies a picked file into the app's temp directory so every upload reads
  /// from a normal path, which is what the chunked reader needs.
  Future<void> _adoptSelection(
    String path,
    String fileName, {
    required bool isVideo,
  }) async {
    setState(() {
      _isPreparing = true;
      _error = null;
      _thumbnail = null;
      _durationSeconds = 0;
    });

    try {
      final directory = await getTemporaryDirectory();
      final target = File('${directory.path}/upload-${_uniqueId()}-$fileName');
      await File(path).copy(target.path);
      final workingPath = target.path;

      final selection = UploadSelection(
        path: workingPath,
        fileName: fileName,
        isVideo: isVideo,
        isTemporary: true,
      );

      final duration = await VideoThumbnails.durationSeconds(workingPath);
      Uint8List? thumbnail;
      if (isVideo) {
        thumbnail = await VideoThumbnails.fromVideo(
          workingPath,
          seconds: duration > 3 ? 1 : 0,
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _selection = selection;
        _thumbnail = thumbnail;
        _durationSeconds = duration;
        if (_title.text.trim().isEmpty) {
          _title.text = _titleFromFileName(fileName);
        }
      });
    } on Exception catch (error) {
      _fail('Could not read that file ($error)');
    } finally {
      if (mounted) {
        setState(() => _isPreparing = false);
      }
    }
  }

  static String _uniqueId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static String _titleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    var base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final parts = base.split('-');
    if (parts.length >= 3) {
      base = parts.sublist(2).join('-');
    }
    return base.replaceAll('_', ' ').trim();
  }

  // MARK: - Upload

  Future<void> _startUpload() async {
    final state = AppScope.of(context);
    final toast = AppScope.toastOf(context);

    final credentials = state.adminCredentials;
    final selection = _selection;
    final title = _title.text.trim();
    final rabbi = _rabbi.text.trim();

    if (credentials == null) {
      _fail(
        'Admin credentials are missing. Sign in with an admin Google account '
        'and save the upload password in Account.',
      );
      return;
    }
    if (selection == null) {
      _fail('Choose a file to upload first.');
      return;
    }
    if (title.isEmpty || rabbi.isEmpty) {
      _fail('Title and speaker are both required.');
      return;
    }

    setState(() {
      _isUploading = true;
      _progress = 0;
      _status = 'Starting…';
      _error = null;
    });

    try {
      final uploader = ShiurUploader(api: state.api);
      await uploader.upload(
        request: ShiurUploadRequest(
          selection: selection,
          title: title,
          rabbi: rabbi,
          date: _date.text.trim(),
          thumbnailJpeg: _thumbnail,
        ),
        credentials: credentials,
        onProgress: (double fraction, String status) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = fraction;
            _status = status;
          });
        },
      );

      await state.refresh();
      if (!mounted) {
        return;
      }
      toast.show('Uploaded "$title"');
      setState(() {
        _selection = null;
        _thumbnail = null;
        _durationSeconds = 0;
        _title.clear();
        _progress = 0;
        _status = '';
      });
    } on UploadFailure catch (error) {
      _fail(error.message);
    } on ApiException catch (error) {
      _fail(error.message);
    } on Exception catch (error) {
      _fail('Upload failed ($error)');
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _error = message);
    AppScope.toastOf(context).show(message, kind: ToastKind.error);
  }

  // MARK: - Build

  @override
  Widget build(BuildContext context) {
    return StateBuilder(
      builder: (BuildContext context, AppState state) =>
          _screen(context, state),
    );
  }

  Widget _screen(BuildContext context, AppState state) {
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Upload Shiur'),
        prefixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.arrowLeft),
            onPress: () => Navigator.of(context).pop(),
            semanticsLabel: 'Back',
          ),
        ],
      ),
      child: AbsorbPointer(
        absorbing: _isUploading,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: <Widget>[
            if (!state.isSignedIn || !state.isAdmin)
              _GateNotice(state: state)
            else if (state.adminCredentials == null)
              const FAlert(
                title: Text('Upload password needed'),
                subtitle: Text(
                  'The worker checks X-Upload-Password on every admin request. '
                  'Open Account, enter the upload password and save it before '
                  'uploading.',
                ),
                icon: Icon(FLucideIcons.key),
              ),
            const SizedBox(height: 18),
            FTextField(
              control: FTextFieldControl.managed(controller: _title),
              label: const Text('Title'),
              hint: 'Parsha',
            ),
            const SizedBox(height: 16),
            FTextField(
              control: FTextFieldControl.managed(controller: _rabbi),
              label: const Text('Speaker'),
              hint: 'Rabbi Hartman',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _rabbis
                  .map(
                    (String value) => FButton(
                      variant: FButtonVariant.outline,
                      size: FButtonSizeVariant.sm,
                      onPress: () => setState(() => _rabbi.text = value),
                      child: Text(
                        value == 'guests' ? 'Guest Speakers' : value,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            FTextField(
              control: FTextFieldControl.managed(controller: _date),
              label: const Text('Date (yyyy-MM-dd)'),
              hint: '2026-10-14',
            ),
            const SizedBox(height: 18),
            _selectionCard(),
            const SizedBox(height: 22),
            if (_isUploading) ...<Widget>[
              FDeterminateProgress(value: _progress.clamp(0, 1)),
              const SizedBox(height: 8),
              Text(
                '$_status ${(_progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 13,
                  color: context.palette.textMuted,
                ),
              ),
              const SizedBox(height: 16),
            ],
            FButton(
              onPress: _isUploading || _isPreparing ? null : _startUpload,
              child: Text(_isUploading ? 'Uploading…' : 'Publish Shiur'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              FAlert(
                title: const Text('Upload failed'),
                subtitle: Text(_error!),
                icon: const Icon(FLucideIcons.circleAlert),
                variant: FAlertVariant.destructive,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectionCard() {
    final palette = context.palette;
    final selection = _selection;

    return Tint(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                selection == null
                    ? FLucideIcons.upload
                    : (selection.isVideo
                        ? FLucideIcons.squarePlay
                        : FLucideIcons.music),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  selection == null ? 'No file selected' : selection.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textMain,
                  ),
                ),
              ),
            ],
          ),
          if (selection != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              <String>[
                selection.isVideo ? 'Video' : 'Audio',
                if (_durationSeconds > 0)
                  '${(_durationSeconds / 60).toStringAsFixed(1)} min',
                if (_selectionBytes() != null)
                  '${(_selectionBytes()! / (1024 * 1024)).toStringAsFixed(1)} MB',
                if (selection.isVideo && _thumbnail == null)
                  'no thumbnail generated',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
            if (_thumbnail != null) ...<Widget>[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _thumbnail!,
                  height: 118,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: _isPreparing || _isUploading
                      ? null
                      : _pickFromLibrary,
                  prefix: const Icon(FLucideIcons.image, size: 15),
                  child: const Text('Photos', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: _isPreparing || _isUploading ? null : _pickFromFiles,
                  prefix: const Icon(FLucideIcons.folderOpen, size: 15),
                  child: const Text('Files', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
          if (_isPreparing) ...<Widget>[
            const SizedBox(height: 14),
            const FCircularProgress(size: FCircularProgressSizeVariant.sm),
            const SizedBox(height: 8),
            Text(
              'Reading the file and generating a thumbnail…',
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  int? _selectionBytes() {
    final selection = _selection;
    if (selection == null) {
      return null;
    }
    try {
      return File(selection.path).lengthSync();
    } on FileSystemException {
      return null;
    }
  }
}

/// Shown when the signed-in account isn't allowed to publish.
class _GateNotice extends StatelessWidget {
  const _GateNotice({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isSignedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const FAlert(
            title: Text('Sign in to upload'),
            subtitle: Text(
              'Publishing needs an admin Google account. Sign in from Account, '
              'then come back here.',
            ),
            icon: Icon(FLucideIcons.lock),
          ),
          const SizedBox(height: 12),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => AppRoutes.openAccount(context),
            child: const Text('Open Account'),
          ),
        ],
      );
    }
    return FAlert(
      title: const Text('Not an admin account'),
      subtitle: Text(
        '${state.user?.email ?? 'This account'} is not on the publisher list, '
        'so the worker will reject the upload.',
      ),
      icon: const Icon(FLucideIcons.circleX),
      variant: FAlertVariant.destructive,
    );
  }
}
