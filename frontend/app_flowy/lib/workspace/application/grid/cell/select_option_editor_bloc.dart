import 'dart:async';
import 'package:app_flowy/workspace/application/grid/field/grid_listenr.dart';
import 'package:dartz/dartz.dart';
import 'package:flowy_sdk/log.dart';
import 'package:flowy_sdk/protobuf/flowy-grid/selection_type_option.pb.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:app_flowy/workspace/application/grid/cell/cell_service/cell_service.dart';
import 'select_option_service.dart';
import 'package:collection/collection.dart';

part 'select_option_editor_bloc.freezed.dart';

class SelectOptionCellEditorBloc extends Bloc<SelectOptionEditorEvent, SelectOptionEditorState> {
  final SelectOptionService _selectOptionService;
  final GridSelectOptionCellContext cellContext;
  late final GridFieldsListener _fieldListener;
  void Function()? _onCellChangedFn;
  Timer? _delayOperation;

  SelectOptionCellEditorBloc({
    required this.cellContext,
  })  : _selectOptionService = SelectOptionService(gridCell: cellContext.gridCell),
        _fieldListener = GridFieldsListener(gridId: cellContext.gridId),
        super(SelectOptionEditorState.initial(cellContext)) {
    on<SelectOptionEditorEvent>(
      (event, emit) async {
        await event.map(
          initial: (_Initial value) async {
            _startListening();
            _loadOptions();
          },
          didReceiveOptions: (_DidReceiveOptions value) {
            final result = _makeOptions(state.filter, value.options);
            emit(state.copyWith(
              allOptions: value.options,
              options: result.options,
              createOption: result.createOption,
              selectedOptions: value.selectedOptions,
            ));
          },
          newOption: (_NewOption value) {
            _createOption(value.optionName);
            emit(state.copyWith(
              filter: none(),
            ));
          },
          deleteOption: (_DeleteOption value) {
            _deleteOption(value.option);
          },
          updateOption: (_UpdateOption value) {
            _updateOption(value.option);
          },
          selectOption: (_SelectOption value) {
            _onSelectOption(value.optionId);
          },
          filterOption: (_SelectOptionFilter value) {
            _filterOption(value.optionName, emit);
          },
        );
      },
    );
  }

  @override
  Future<void> close() async {
    if (_onCellChangedFn != null) {
      cellContext.removeListener(_onCellChangedFn!);
      _onCellChangedFn = null;
    }
    _delayOperation?.cancel();
    await _fieldListener.stop();
    cellContext.dispose();
    return super.close();
  }

  void _createOption(String name) async {
    final result = await _selectOptionService.create(name: name);
    result.fold((l) => {}, (err) => Log.error(err));
  }

  void _deleteOption(SelectOption option) async {
    final result = await _selectOptionService.delete(
      option: option,
    );

    result.fold((l) => null, (err) => Log.error(err));
  }

  void _updateOption(SelectOption option) async {
    final result = await _selectOptionService.update(
      option: option,
    );

    result.fold((l) => null, (err) => Log.error(err));
  }

  void _onSelectOption(String optionId) {
    final hasSelected = state.selectedOptions.firstWhereOrNull((option) => option.id == optionId);
    if (hasSelected != null) {
      _selectOptionService.unSelect(optionId: optionId);
    } else {
      _selectOptionService.select(optionId: optionId);
    }
  }

  void _filterOption(String optionName, Emitter<SelectOptionEditorState> emit) {
    final _MakeOptionResult result = _makeOptions(Some(optionName), state.allOptions);
    emit(state.copyWith(
      filter: Some(optionName),
      options: result.options,
      createOption: result.createOption,
    ));
  }

  void _loadOptions() {
    _delayOperation?.cancel();
    _delayOperation = Timer(const Duration(milliseconds: 10), () {
      _selectOptionService.getOpitonContext().then((result) {
        if (isClosed) {
          return;
        }
        return result.fold(
          (data) => add(SelectOptionEditorEvent.didReceiveOptions(data.options, data.selectOptions)),
          (err) {
            Log.error(err);
            return null;
          },
        );
      });
    });
  }

  _MakeOptionResult _makeOptions(Option<String> filter, List<SelectOption> allOptions) {
    final List<SelectOption> options = List.from(allOptions);
    Option<String> createOption = filter;

    filter.foldRight(null, (filter, previous) {
      if (filter.isNotEmpty) {
        options.retainWhere((option) {
          final name = option.name.toLowerCase();
          final lFilter = filter.toLowerCase();

          if (name == lFilter) {
            createOption = none();
          }

          return name.contains(lFilter);
        });
      }
    });

    return _MakeOptionResult(
      options: options,
      createOption: createOption,
    );
  }

  void _startListening() {
    _onCellChangedFn = cellContext.startListening(
      onCellChanged: ((selectOptionContext) {
        if (!isClosed) {
          _loadOptions();
        }
      }),
    );

    _fieldListener.start(onFieldsChanged: (result) {
      result.fold(
        (changeset) {
          if (changeset.updatedFields.isNotEmpty) {
            _loadOptions();
          }
        },
        (err) => Log.error(err),
      );
    });
  }
}

@freezed
class SelectOptionEditorEvent with _$SelectOptionEditorEvent {
  const factory SelectOptionEditorEvent.initial() = _Initial;
  const factory SelectOptionEditorEvent.didReceiveOptions(
      List<SelectOption> options, List<SelectOption> selectedOptions) = _DidReceiveOptions;
  const factory SelectOptionEditorEvent.newOption(String optionName) = _NewOption;
  const factory SelectOptionEditorEvent.selectOption(String optionId) = _SelectOption;
  const factory SelectOptionEditorEvent.updateOption(SelectOption option) = _UpdateOption;
  const factory SelectOptionEditorEvent.deleteOption(SelectOption option) = _DeleteOption;
  const factory SelectOptionEditorEvent.filterOption(String optionName) = _SelectOptionFilter;
}

@freezed
class SelectOptionEditorState with _$SelectOptionEditorState {
  const factory SelectOptionEditorState({
    required List<SelectOption> options,
    required List<SelectOption> allOptions,
    required List<SelectOption> selectedOptions,
    required Option<String> createOption,
    required Option<String> filter,
  }) = _SelectOptionEditorState;

  factory SelectOptionEditorState.initial(GridSelectOptionCellContext context) {
    final data = context.getCellData(loadIfNoCache: false);
    return SelectOptionEditorState(
      options: data?.options ?? [],
      allOptions: data?.options ?? [],
      selectedOptions: data?.selectOptions ?? [],
      createOption: none(),
      filter: none(),
    );
  }
}

class _MakeOptionResult {
  List<SelectOption> options;
  Option<String> createOption;

  _MakeOptionResult({
    required this.options,
    required this.createOption,
  });
}
