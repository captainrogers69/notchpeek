import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';

class SetMediaPolling {
  const SetMediaPolling(this._repository);

  final MusicRepository _repository;

  Future<ApiResponse<bool>> call(bool enabled) =>
      _repository.setPolling(enabled);
}
