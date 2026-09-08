import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

class SendMediaCommand {
  const SendMediaCommand(this._repository);

  final MusicRepository _repository;

  Future<ApiResponse<bool>> call(MediaCommand command, {Duration? seekTo}) =>
      _repository.command(command, seekTo: seekTo);
}
