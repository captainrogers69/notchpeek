import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/features/music/data/datasources/music_datasource.dart';
import 'package:notchpeek/features/music/data/repositories/music_repository_impl.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/features/music/domain/usecases/open_player.dart';
import 'package:notchpeek/features/music/domain/usecases/send_media_command.dart';
import 'package:notchpeek/features/music/domain/usecases/set_media_polling.dart';
import 'package:notchpeek/features/music/domain/usecases/watch_now_playing.dart';
import 'package:notchpeek/features/music/presentation/notifier/music_notifier.dart';

final musicDataSourceProvider = Provider<MusicDataSource>(
  (ref) => MusicDataSourceImpl(ref.watch(channelServiceProvider)),
);

final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => MusicRepositoryImpl(ref.watch(musicDataSourceProvider)),
);

final watchNowPlayingProvider = Provider<WatchNowPlaying>(
  (ref) => WatchNowPlaying(ref.watch(musicRepositoryProvider)),
);

final sendMediaCommandProvider = Provider<SendMediaCommand>(
  (ref) => SendMediaCommand(ref.watch(musicRepositoryProvider)),
);

final setMediaPollingProvider = Provider<SetMediaPolling>(
  (ref) => SetMediaPolling(ref.watch(musicRepositoryProvider)),
);

final openPlayerProvider = Provider<OpenPlayer>(
  (ref) => OpenPlayer(ref.watch(musicRepositoryProvider)),
);

/// Watched even while collapsed: track changes arrive as distributed
/// notifications and are what fires the peek. The *tick* is what gets gated,
/// through [mediaPollingProvider].
final nowPlayingProvider = StreamProvider<NowPlaying>(
  (ref) => ref.watch(watchNowPlayingProvider)(),
);

final musicNotifierProvider = NotifierProvider<MusicNotifier, NowPlaying>(
  MusicNotifier.new,
);

final mediaPollingProvider = NotifierProvider<MediaPollingNotifier, bool>(
  MediaPollingNotifier.new,
);
