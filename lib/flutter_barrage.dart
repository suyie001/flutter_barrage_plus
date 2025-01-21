library flutter_barrage;

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:quiver/collection.dart';
import 'package:flutter/rendering.dart';

const TAG = 'FlutterBarrage';

enum Status {
  idle,
  loading,
  playing,
  switching,
}

// 添加弹幕区域枚举
enum BarrageArea {
  top, // 顶部区域
  middle, // 中间区域
  bottom, // 底部区域
  full, // 铺满全屏
}

class BarrageWall extends StatefulWidget {
  final BarrageWallController controller;

  /// the bullet widget
  final Widget child;

  /// time in seconds of bullet show in screen
  final int speed;

  /// used to adjust speed for each channel
  final int speedCorrectionInMilliseconds;

  final double width;
  final double height;

  /// will not send bullets to the area is safe from bottom, default is 0
  /// used to not cover the subtitles
  final int safeBottomHeight;

  /// [disable] by default, set to true will overwrite other bullets
  final bool massiveMode;

  /// used to make barrage tidy
  final double maxBulletHeight;

  /// enable debug mode, will display a debug panel with information
  final bool debug;
  final bool selfCreatedController;

  /// 弹幕显示区域
  final BarrageArea area;

  /// 每个区域的高度占比 (0.0 - 1.0)
  final double areaHeightRatio;

  BarrageWall({
    List<Bullet>? bullets,
    BarrageWallController? controller,
    ValueNotifier<BarrageValue>? timelineNotifier,
    this.speed = 5,
    this.child = const SizedBox(),
    required this.width,
    required this.height,
    this.massiveMode = false,
    this.maxBulletHeight = 16,
    this.debug = false,
    this.safeBottomHeight = 0,
    this.speedCorrectionInMilliseconds = 3000,
    this.area = BarrageArea.full,
    this.areaHeightRatio = 0.3, // 默认每个区域占30%的高度
  })  : controller = controller ?? BarrageWallController.withBarrages(bullets, timelineNotifier: timelineNotifier),
        selfCreatedController = controller == null,
        assert(areaHeightRatio > 0 && areaHeightRatio <= 1.0) {
    if (controller != null) {
      this.controller.value = controller.value.size == 0 ? BarrageWallValue.fromList(bullets ?? []) : controller.value;
      this.controller.timelineNotifier = controller.timelineNotifier ?? timelineNotifier;
    }
  }

  @override
  State<StatefulWidget> createState() => _BarrageState();
}

/// It's a class that holds the position of a bullet
class BulletPos {
  int id;
  int channel;
  double position; // from right to left
  double width;
  bool released = false;
  int lifetime;
  Widget widget;
  double height;
  double estimatedWidth;

  BulletPos({
    required this.id,
    required this.channel,
    required this.position,
    required this.width,
    required this.widget,
    required this.height,
    required this.estimatedWidth,
  }) : lifetime = DateTime.now().millisecondsSinceEpoch;

  updateWith({required double position, double width = 0}) {
    this.position = position;
    this.width = width > 0 ? width : this.width;
    this.lifetime = DateTime.now().millisecondsSinceEpoch;
//    debugPrint("[$TAG] update to $this");
  }

  bool get hasExtraSpace {
    return position > width + 8;
  }

  @override
  String toString() {
    return 'BulletPos{id: $id, channel: $channel, position: $position, width: $width, released: $released, widget: $widget}';
  }
}

/// 通道信息类
class ChannelInfo {
  double height; // 通道高度
  double yPosition; // 通道Y轴位置
  bool occupied; // 是否被占用
  double lastBulletEnd; // 最后一个弹幕的预计结束位置

  ChannelInfo({
    required this.height,
    required this.yPosition,
    this.occupied = false,
    this.lastBulletEnd = 0,
  });
}

class _BarrageState extends State<BarrageWall> with TickerProviderStateMixin {
  late BarrageWallController _controller;
  Random _random = new Random();
  double? _lastHeight;

  double? _maxBulletHeight;
  int? _totalChannels;
  int? _channelMask;
  List<int> _speedCorrectionForChannels = [];

  // 通道信息列表
  List<ChannelInfo> _channels = [];

  // 添加帧率控制
  static const int TARGET_FPS = 60;
  int _lastFrameTime = 0;

  // 弹幕信息列表
  final List<BulletInfo> _bulletInfos = [];

  // 初始化通道
  void _initializeChannels() {
    _channels.clear();
    final (areaStart, areaEnd) = _calculateAreaRange(widget.height);

    // 初始化默认通道
    double currentY = areaStart;
    while (currentY + widget.maxBulletHeight <= areaEnd) {
      _channels.add(ChannelInfo(
        height: widget.maxBulletHeight,
        yPosition: currentY,
      ));
      currentY += widget.maxBulletHeight;
    }
  }

  // 估算弹幕宽度
  double _estimateBulletWidth(Widget bullet) {
    // 使用 TextPainter 估算文本宽度
    if (bullet is Text) {
      final textPainter = TextPainter(
        text: TextSpan(text: bullet.data, style: bullet.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return textPainter.width + 20; // 添加一些padding
    }
    // 其他类型Widget使用默认宽度
    return 100.0;
  }

  // 智能选择通道
  int? _selectChannel(double bulletWidth) {
    if (_channels.isEmpty) return null;

    // 计算最佳通道
    int? bestChannel;
    double bestScore = double.infinity;

    for (int i = 0; i < _channels.length; i++) {
      if (_channels[i].occupied) continue;

      // 计算该通道的拥挤度分数
      double score = _channels[i].lastBulletEnd;

      // 考虑相邻通道的情况
      if (i > 0) score += _channels[i - 1].lastBulletEnd * 0.5;
      if (i < _channels.length - 1) score += _channels[i + 1].lastBulletEnd * 0.5;

      // 更新最佳通道
      if (score < bestScore) {
        bestScore = score;
        bestChannel = i;
      }
    }

    return bestChannel;
  }

  // 计算弹幕区域的范围
  (double start, double end) _calculateAreaRange(double totalHeight) {
    switch (widget.area) {
      case BarrageArea.top:
        return (0, totalHeight * widget.areaHeightRatio);
      case BarrageArea.middle:
        final areaHeight = totalHeight * widget.areaHeightRatio;
        final start = (totalHeight - areaHeight) / 2;
        return (start, start + areaHeight);
      case BarrageArea.bottom:
        final areaHeight = totalHeight * widget.areaHeightRatio;
        return (totalHeight - areaHeight, totalHeight);
      case BarrageArea.full:
        return (0, totalHeight);
    }
  }

  // 修改计算通道数的方法
  int _calcSafeHeight(double height) {
    if (height.isInfinite) {
      final toHeight = context.size!.height;
      debugPrint("[$TAG] height is infinite, set it to $toHeight");
      return toHeight.toInt();
    } else {
      final safeBottomHeight = _controller.safeBottomHeight ?? widget.safeBottomHeight;
      final (start, end) = _calculateAreaRange(height);
      final areaHeight = end - start - safeBottomHeight;

      debugPrint('[$TAG] area: ${widget.area}, height: $areaHeight');
      if (areaHeight < 0) {
        throw Exception('Invalid area height: $areaHeight');
      }
      return areaHeight.toInt();
    }
  }

  // 修改弹幕处理方法
  void _handleBullets(
    BuildContext context, {
    required List<Bullet> bullets,
    required double width,
    double? end,
  }) {
    end ??= width * 2;

    // 确保通道已初始化
    if (_channels.isEmpty) {
      _initializeChannels();
    }

    // 更新通道状态
    for (var channel in _channels) {
      channel.occupied = false;
      if (channel.lastBulletEnd > 0) {
        channel.lastBulletEnd -= 16.0; // 随时间减少占用
        if (channel.lastBulletEnd < 0) channel.lastBulletEnd = 0;
      }
    }

    // 帧率控制
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameTime < (1000 / TARGET_FPS)) {
      return;
    }
    _lastFrameTime = now;

    bullets.forEach((Bullet bullet) {
      // 估算弹幕宽度
      final estimatedWidth = _estimateBulletWidth(bullet.child);

      // 选择最佳通道
      final channelIndex = _selectChannel(estimatedWidth);
      if (channelIndex == null) return;

      final channel = _channels[channelIndex];
      channel.occupied = true;
      channel.lastBulletEnd = width + estimatedWidth;

      // 创建弹幕信息
      final bulletInfo = BulletInfo(
        child: bullet.child,
        position: Offset(width, channel.yPosition),
        size: Size(estimatedWidth, channel.height),
        context: context,
      );

      // 添加到渲染列表
      _bulletInfos.add(bulletInfo);

      // 创建动画
      final showTimeInMilliseconds = widget.speed * 2 * 1000 - _speedCorrectionForChannels[channelIndex];

      final animationController = AnimationController(
        duration: Duration(milliseconds: showTimeInMilliseconds),
        vsync: this,
      );

      Animation<double> animation = Tween<double>(
        begin: width,
        end: -estimatedWidth,
      ).animate(animationController..forward());

      // 更新弹幕位置
      animation.addListener(() {
        bulletInfo.position = Offset(animation.value, channel.yPosition);
      });

      // 动画结束时清理
      animationController.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _bulletInfos.remove(bulletInfo);
          animationController.dispose();
        }
      });
    });
  }

  @override
  void didUpdateWidget(BarrageWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller = widget.controller;
    }
  }

  void handleBullets() {
    if (_controller.isEnabled && _controller.value.waitingList.isNotEmpty) {
      final recallNeeded = _lastHeight != widget.height || _channelMask == null;

      if (_totalChannels == null || recallNeeded) {
        _lastHeight = widget.height;
        _maxBulletHeight = widget.maxBulletHeight;
        _totalChannels = _calcSafeHeight(widget.height) ~/ _maxBulletHeight!;
        debugPrint("[$TAG] total channels: ${_totalChannels! + 1}");
        _channelMask = (2 << _totalChannels!) - 1;

        for (var i = 0; i <= _totalChannels!; i++) {
          final nextSpeed = widget.speedCorrectionInMilliseconds > 0 ? _random.nextInt(widget.speedCorrectionInMilliseconds) : 0;
          _speedCorrectionForChannels.add(nextSpeed);
        }
      }

      _handleBullets(
        context,
        bullets: _controller.value.waitingList,
        width: widget.width,
      );
      // _processed += _controller.value.waitingList.length;
      setState(() {});
    }
  }

  @override
  void initState() {
    _controller = widget.controller;
    _controller.initialize();

    _controller.addListener(handleBullets);
    _controller.enabledNotifier.addListener(() {
      setState(() {});
    });

    // 移除定时清理器，改用动画状态监听
    // _cleaner = Timer.periodic(...);

    super.initState();
  }

  @override
  void dispose() {
    debugPrint('[$TAG] dispose');
    // _cleaner.cancel(); // 移除这行
    _controller.clear();
    _controller.removeListener(handleBullets);
    if (widget.selfCreatedController) {
      _controller.dispose();
    }
    _channels.clear();
    for (var bullet in _bulletInfos) {
      bullet.dispose();
    }
    _bulletInfos.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.visibilityNotifier,
      builder: (context, isVisible, child) {
        if (!isVisible) {
          return const SizedBox(); // 不显示弹幕
        }

        return Stack(
          children: [
            // 实际渲染的弹幕
            ..._bulletInfos
                .map((bullet) => Positioned(
                      left: bullet.position.dx,
                      top: bullet.position.dy,
                      child: SizedBox(
                        width: bullet.size.width,
                        height: bullet.size.height,
                        child: bullet.child,
                      ),
                    ))
                .toList(),

            // 用于调试的 CustomPaint
            if (widget.debug)
              CustomPaint(
                painter: DebugPainter(
                  bullets: _bulletInfos,
                ),
                size: Size(widget.width, widget.height),
              ),
          ],
        );
      },
    );
  }
}

typedef int KeyCalculator<T>(T t);

class HashList<T> {
  /// key is the showTime in minutes
  Map<int, TreeSet<T>> _map = new HashMap();
  final Comparator<T>? comparator;
  final KeyCalculator<T> keyCalculator;

  HashList({required this.keyCalculator, this.comparator});

  void appendByMinutes(List<T> values) {
    values.forEach((value) {
      int key = keyCalculator(value);
      if (_map.containsKey(key)) {
        _map[key]!.add(value);
      } else {
        _map.putIfAbsent(key, () => TreeSet<T>(comparator: comparator ?? (dynamic a, b) => a.compareTo(b))..add(value));
      }
    });
  }

  @override
  String toString() {
    return 'HashList{$_map}';
  }
}

class BarrageValue {
  final int timeline;
  final bool isPlaying;

  BarrageValue({this.timeline = -1, this.isPlaying = false});

  BarrageValue copyWith({int? timeline, bool? isPlaying}) => BarrageValue(timeline: timeline ?? this.timeline, isPlaying: isPlaying ?? this.isPlaying);

  @override
  String toString() {
    return 'BarrageValue{timeline: $timeline, isPlaying: $isPlaying}';
  }
}

class BarrageWallValue {
  final int showedTimeBefore;
  final int size;
  final int processedSize;
  final List<Bullet> waitingList;

  final HashList<Bullet> bullets;

  BarrageWallValue.fromList(List<Bullet> bullets, {this.showedTimeBefore = 0, this.waitingList = const []})
      : bullets = HashList<Bullet>(keyCalculator: (t) => Duration(milliseconds: t.showTime).inMinutes)..appendByMinutes(bullets),
        size = bullets.length,
        processedSize = 0;

  BarrageWallValue({
    required this.bullets,
    this.showedTimeBefore = 0,
    this.waitingList = const [],
    this.size = 0,
    this.processedSize = 0,
  });

  BarrageWallValue copyWith({
    // int lastProcessedTime,
    required int processedSize,
    int? showedTimeBefore,
    List<Bullet>? waitingList,
  }) =>
      BarrageWallValue(
        bullets: bullets,
        showedTimeBefore: showedTimeBefore ?? this.showedTimeBefore,
        waitingList: waitingList ?? this.waitingList,
        size: this.size,
        processedSize: this.processedSize + processedSize,
      );

  @override
  String toString() {
    return 'BarrageWallValue{showedTimeBefore: $showedTimeBefore, size: $size, processed: $processedSize, waitings: ${waitingList.length}}';
  }
}

class BarrageWallController extends ValueNotifier<BarrageWallValue> {
  Map<AnimationController, Widget> _widgets = new LinkedHashMap();
  Map<dynamic, BulletPos> _lastBullets = {};
  int _usedChannel = 0;

  int timeline = 0;
  ValueNotifier<bool> enabledNotifier = ValueNotifier(true);
  bool _isDisposed = false;

  ValueNotifier<BarrageValue>? timelineNotifier;
  int? safeBottomHeight;
  Timer? _timer;

  bool get isEnabled => enabledNotifier.value;
  Map<AnimationController, Widget> get widgets => _widgets;
  Map<dynamic, BulletPos> get lastBullets => _lastBullets;
  int get usedChannel => _usedChannel;

  Status _status = Status.idle;
  Status get status => _status;

  // 添加错误处理
  String? _error;
  String? get error => _error;

  // 添加容量限制配置
  static const int DEFAULT_MAX_BULLETS = 200;
  final int maxBullets;

  // 添加对象池
  final Queue<BulletPos> _bulletPool = Queue();
  static const int POOL_SIZE = 50;

  // 添加暂停状态
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  // 添加显示控制
  final ValueNotifier<bool> visibilityNotifier = ValueNotifier(true);
  bool get isVisible => visibilityNotifier.value;

  // 初始化对象池
  void _initPool() {
    for (var i = 0; i < POOL_SIZE; i++) {
      _bulletPool.add(BulletPos(
        id: -1,
        channel: -1,
        position: 0,
        width: 0,
        height: 0,
        estimatedWidth: 0,
        widget: const SizedBox(),
      ));
    }
  }

  // 从对象池获取对象
  BulletPos _obtainBulletPos({
    required int id,
    required int channel,
    required double position,
    required double width,
    required double height,
    required double estimatedWidth,
    required Widget widget,
  }) {
    final bulletPos = _bulletPool.isEmpty
        ? BulletPos(
            id: id,
            channel: channel,
            position: position,
            width: width,
            height: height,
            estimatedWidth: estimatedWidth,
            widget: widget,
          )
        : _bulletPool.removeFirst()
      ..id = id
      ..channel = channel
      ..position = position
      ..width = width
      ..height = height
      ..estimatedWidth = estimatedWidth
      ..widget = widget
      ..released = false
      ..lifetime = DateTime.now().millisecondsSinceEpoch;

    return bulletPos;
  }

  // 回收对象到对象池
  void _recycleBulletPos(BulletPos bulletPos) {
    if (_bulletPool.length < POOL_SIZE) {
      _bulletPool.add(bulletPos);
    }
  }

  // 修改 tryFire 方法，添加容量限制
  @override
  void tryFire({List<Bullet> bullets = const []}) {
    if (_status != Status.playing || _isPaused) return;

    // 检查容量限制
    if (_widgets.length >= maxBullets) {
      debugPrint('[$TAG] Reached max bullets limit: $maxBullets');
      return;
    }

    final key = Duration(milliseconds: timeline).inMinutes;
    final exists = value.bullets._map.containsKey(key);

    if (exists || bullets.isNotEmpty) {
      List<Bullet> toBePrecessed =
          value.bullets._map[key]?.where((barrage) => barrage.showTime > value.showedTimeBefore && barrage.showTime <= timeline).toList() ?? [];

      // 限制待处理弹幕数量
      final remainingCapacity = maxBullets - _widgets.length;
      if (toBePrecessed.length + bullets.length > remainingCapacity) {
        final totalBullets = [...toBePrecessed, ...bullets];
        toBePrecessed = totalBullets.take(remainingCapacity).toList();
      }

      if (toBePrecessed.isNotEmpty) {
        value = value.copyWith(
          showedTimeBefore: timeline,
          waitingList: toBePrecessed,
          processedSize: toBePrecessed.length,
        );
      }
    }
  }

  // 优化资源释放
  @override
  Future<void> clear() async {
    await _disposeAnimationControllers();

    // 回收所有 BulletPos 对象
    _lastBullets.values.forEach(_recycleBulletPos);
    _lastBullets.clear();

    _usedChannel = 0;
    timeline = 0;
    _status = Status.idle;
  }

  // 添加错误处理和状态管理方法
  void _handleError(String message, [Exception? error]) {
    _error = message;
    _status = Status.idle;
    debugPrint('[$TAG] Error: $message${error != null ? ', $error' : ''}');
  }

  bool get canAcceptMoreBullets => _status == Status.playing && _widgets.length < maxBullets;

  // 修改发送弹幕方法
  void send(List<Bullet> bullets) {
    if (!canAcceptMoreBullets) {
      _handleError('Cannot accept more bullets: status=$_status, count=${_widgets.length}');
      return;
    }
    tryFire(bullets: bullets);
  }

  // 优化资源释放
  Future<void> _disposeAnimationControllers() async {
    for (final controller in _widgets.keys) {
      controller.stop();
      controller.dispose();
    }
    _widgets.clear();
  }

  // 添加内容切换方法
  Future<void> switchContent({
    List<Bullet>? newBullets,
    bool clearOld = true,
  }) async {
    try {
      _status = Status.switching;
      _error = null;
      _isPaused = false; // 重置暂停状态

      // 停止当前动画和清理资源
      if (clearOld) {
        await _disposeAnimationControllers();
        _lastBullets.clear();
        _usedChannel = 0;
      }

      // 重置状态
      timeline = 0;
      value = BarrageWallValue.fromList(newBullets ?? []);

      _status = Status.playing;
    } catch (e) {
      _error = e.toString();
      _status = Status.idle;
      debugPrint('[$TAG] Error switching content: $e');
    }
  }

  // 暂停所有弹幕动画
  void pause() {
    if (_isPaused) return;
    _isPaused = true;

    // 暂停所有动画
    for (final controller in _widgets.keys) {
      controller.stop();
    }

    // 暂停定时器
    _timer?.cancel();
  }

  // 恢复所有弹幕动画
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;

    // 恢复所有动画
    for (final controller in _widgets.keys) {
      controller.forward();
    }

    // 重新启动定时器
    if (timelineNotifier == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (Timer timer) async {
        if (_isDisposed || _isPaused) {
          timer.cancel();
          return;
        }

        if (value.size == value.processedSize) {
          return;
        }

        timeline += 100;
        tryFire();
      });
    }
  }

  // 显示弹幕
  void show() {
    if (!visibilityNotifier.value) {
      visibilityNotifier.value = true;
      resume(); // 恢复动画
    }
  }

  // 隐藏弹幕
  void hide() {
    if (visibilityNotifier.value) {
      visibilityNotifier.value = false;
      pause(); // 暂停动画
    }
  }

  // 切换显示状态
  void toggleVisibility() {
    if (visibilityNotifier.value) {
      hide();
    } else {
      show();
    }
  }

  BarrageWallController({
    List<Bullet>? bullets,
    this.timelineNotifier,
    this.maxBullets = DEFAULT_MAX_BULLETS,
  }) : super(BarrageWallValue.fromList(bullets ?? const [])) {
    _initPool();
  }

  BarrageWallController.withBarrages(
    List<Bullet>? bullets, {
    this.timelineNotifier,
    this.maxBullets = DEFAULT_MAX_BULLETS,
  }) : super(BarrageWallValue.fromList(bullets ?? const [])) {
    _initPool();
  }

  Future<void> initialize() async {
    final Completer<void> initializingCompleter = Completer<void>();

    if (timelineNotifier == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (Timer timer) async {
        if (_isDisposed) {
          timer.cancel();
          return;
        }

        if (value.size == value.processedSize) {
          /*
          timer.cancel();*/
          return;
        }

        timeline += 100;
        tryFire();
      });
    } else {
      timelineNotifier!.addListener(_handleTimelineNotifier);
    }

    initializingCompleter.complete();
    return initializingCompleter.future;
  }

  /// reset the controller to new time state
  void reset(int showedTimeBefore) {
    value = value.copyWith(showedTimeBefore: showedTimeBefore, waitingList: [], processedSize: 0);
  }

  void updateChannel(Function(int usedChannel) onUpdate) {
    _usedChannel = onUpdate(_usedChannel);
  }

  void _handleTimelineNotifier() {
    final offset = (timeline - timelineNotifier!.value.timeline);
    final ifNeedReset = offset.abs() > 1000;
    if (ifNeedReset) {
      debugPrint("[$TAG] offset: $offset call reset to $timeline...");
      reset(timelineNotifier!.value.timeline);
    }
    if (timelineNotifier != null) timeline = timelineNotifier!.value.timeline;
    tryFire();
  }

  void disable() {
    debugPrint("[$TAG] disable barrage ... current: $enabledNotifier");
    enabledNotifier.value = false;
  }

  void enable() {
    debugPrint("[$TAG] enable barrage ... current: $enabledNotifier");
    enabledNotifier.value = true;
  }

  @override
  Future<void> dispose() async {
    if (!_isDisposed) {
      await clear();
      _timer?.cancel();
    }
    _isDisposed = true;
    timelineNotifier?.dispose();
    enabledNotifier.dispose();
    visibilityNotifier.dispose();
    super.dispose();
  }
}

class Bullet implements Comparable<Bullet> {
  final Widget child;

  /// in milliseconds
  final int showTime;

  const Bullet({required this.child, this.showTime = 0});

  @override
  String toString() {
    return 'Bullet{child: $child, showTime: $showTime}';
  }

  @override
  int compareTo(Bullet other) {
    return showTime.compareTo(other.showTime);
  }
}

// 修改 BulletInfo 类
class BulletInfo {
  final Widget child;
  Offset position;
  Size size;
  final BuildContext context;

  // 使用 GlobalKey 来获取 RenderBox
  final GlobalKey _key = GlobalKey();
  RenderBox? _renderBox;

  BulletInfo({
    required this.child,
    required this.position,
    required this.size,
    required this.context,
  });

  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(position.dx, position.dy);

    if (_renderBox == null) {
      final context = _key.currentContext;
      if (context != null) {
        _renderBox = context.findRenderObject() as RenderBox?;
      }
    }

    if (_renderBox != null && _renderBox!.hasSize) {
      // 使用 layer 进行渲染
      final layer = _renderBox!.layer;
      if (layer != null) {
        layer.addToScene(SceneBuilder());
      }
    } else {
      // 降级方案：渲染占位符
      final paint = Paint()
        ..color = Colors.grey.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        paint,
      );
    }

    canvas.restore();
  }

  void dispose() {
    _renderBox = null;
  }
}

// 添加调试绘制器
class DebugPainter extends CustomPainter {
  final List<BulletInfo> bullets;

  DebugPainter({
    required this.bullets,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var bullet in bullets) {
      final paint = Paint()
        ..color = Colors.red.withOpacity(0.3)
        ..style = PaintingStyle.stroke;
      canvas.drawRect(
        Rect.fromLTWH(
          bullet.position.dx,
          bullet.position.dy,
          bullet.size.width,
          bullet.size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DebugPainter oldDelegate) => true;
}
