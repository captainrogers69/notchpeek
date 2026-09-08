import 'dart:ui';

import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/data/datasources/shell_datasource.dart';
import 'package:notchpeek/features/shell/data/models/hover_model.dart';
import 'package:notchpeek/features/shell/data/models/notch_geometry_model.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';

class ShellRepositoryImpl implements ShellRepository {
  ShellRepositoryImpl(this._source);

  final ShellDataSource _source;

  @override
  Stream<NotchGeometry> watchGeometry() =>
      _source.watchGeometryEvents().map(NotchGeometryModel.toEntity);

  @override
  Stream<bool> watchHover() =>
      _source.watchHoverEvents().map(HoverModel.toEntity);

  @override
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect) =>
      _source.setInteractiveRect(rect);

  @override
  Future<ApiResponse<bool>> performHaptic() => _source.performHaptic();

  @override
  Future<ApiResponse<bool>> quit() => _source.quit();
}
