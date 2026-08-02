/// Brightness state shared by the EPUB and manga readers.
///
/// [override] mirrors the persisted `ReaderSettings.brightness` value —
/// `null` means follow the system brightness. [systemLevel] is the last
/// device brightness read, used to position the slider while no override
/// is active.
class ReaderBrightnessState {
  const ReaderBrightnessState({this.override, this.systemLevel = 0.5});

  final double? override;
  final double systemLevel;

  bool get followsSystem => override == null;

  double get sliderValue => override ?? systemLevel;
}
