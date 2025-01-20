# flutter_barrage

A barrage wall flutter plugin.
一个弹幕墙插件。

## Getting Started

> BarrageWall 需要明确的 width 和 height 来计算可用空间。

#### BarrageWall 参数

* **List<Bullet> bullets** - 初始化的弹幕列表
* **BarrageWallController controller** - 用于初始化后批量发送弹幕的 controller
* **ValueNotifier<BarrageValue> timelineNotifier** - 用于连接媒体的当前播放进度 
* **int speed** - 速度，从屏幕右侧到左侧的时间，默认 5
* **child** - 用于填充的容器
* **double width** - 容器宽度
* **double height** - 容器高度
* **bool massiveMode** - 海量模式，默认关闭，此时当所有通道都被占用时弹幕将被丢弃，不会产生覆盖的情况。当开启式会实时显示所有弹幕，所有通道被占用时会覆盖之前的弹幕。
* **double maxBulletHeight** - 弹幕的最大高度，用于计算通道，默认 16。
* **int speedCorrectionInMilliseconds** - 默认 3000，用于调整不同通道的速度，不同的通道会在这个值的范围内找到一个随机值并调整当前通道的速度
* **bool debug** - 调试模式，会显示一个数据面板
* **int safeBottomHeight** - 默认 0，用于保证在最下方有一个不会显示弹幕的空间，避免挡住字幕

[more examples - 详细用法请查看 examples](https://github.com/danielwii/flutter_barrage/tree/master/example)

* show barrage only

```flutter
List<Bullet> bullets = List<Bullet>.generate(100, (i) {
  final showTime = random.nextInt(60000); // in 60s
  return Bullet(child: Text('$i-$showTime}'), showTime: showTime);
});
Stack(
  children: <Widget>[
    Positioned(
      top: 200,
      width: MediaQuery.of(context).size.width,
      height:
          MediaQuery.of(context).size.width * MediaQuery.of(context).size.aspectRatio + 200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          BarrageWall(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            massiveMode: false, // disabled by default
            timelineNotifier: timelineNotifier, // send a BarrageValue notifier let bullet fires using your own timeline
            bullets: bullets,
          ),
        },
      ),
    )
  ],
);
```

* show barrage with send bullet function

```flutter
Column(
  children: <Widget>[
    Expanded(
      flex: 9,
      child: Stack(
        children: <Widget>[
          Positioned(
            // top: 20,
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.width *
                    MediaQuery.of(context).size.aspectRatio + 100,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return BarrageWall(
                  debug: true, // show debug panel and logs
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  speed: 4, // speed of bullet show in screen (seconds)
                  /*
                  speed: 8,
                  speedCorrectionInMilliseconds: 3000,*/
                  /*
                  timelineNotifier: timelineNotifier, // send a BarrageValue notifier let bullet fires using your own timeline*/
                  bullets: bullets,
                  controller: barrageWallController,
                );
              },
            ),
          ),
        ],
      ),
    ),
    Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: TextField(
          // controller: textEditingController,
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            // controller: textEditingController,
            maxLength: 20,
            onSubmitted: (text) {
              // textEditingController.clear();
              barrageWallController.send([new Bullet(child: Text(text))]);
            })  maxLength: 20,
            onSubmitted: (text) {
              // textEditingController.clear();
              barrageWallController.send([new Bullet(child: Text(text))]);
            },
          ),
        ),
      ),
    ),
  ],
)
```

### Current Features ✅

- **Bullet Customization**
  - Support any Widget as bullet content
  - Configurable speed and channel height
  - Multiple display areas (top, middle, bottom, full)

### Planned Improvements 🚀

1. **Movement Effects**
   - [ ] Smooth enter/exit transitions
   - [ ] Acceleration/deceleration effects
   - [ ] Curved motion paths
   - [ ] Dynamic speed adjustment

2. **Channel Management**
   - [ ] Smart channel allocation based on content length
   - [ ] Dynamic channel height adjustment
   - [ ] Optimized visual distribution

3. **Interactive Features**
   - [ ] Bullet click events
   - [ ] Hover effects
   - [ ] Gesture controls (drag to pause)
   - [ ] Fixed position bullets

4. **Special Effects**
   - [ ] Priority system for important bullets
   - [ ] Timeline-based special effects
   - [ ] Custom motion paths
   - [ ] Group animation effects

## Known Issues

1. Linear movement without smooth transitions
2. Basic channel allocation might cause visual clustering
3. Limited interaction capabilities
4. No support for special bullet types (fixed position, special effects)
