import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';

class OpenPlayer {
  const OpenPlayer(this._repository);

  final MusicRepository _repository;

  Future<ApiResponse<bool>> call(MusicSourceId source) =>
      _repository.openPlayer(source);
}
