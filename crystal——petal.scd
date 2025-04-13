s.boot;
s.scope; // 可选：打开标准示波器

// 1. 你的原始音乐合成部分 ============================================
(
SynthDef(\crystal_mist) { |out=0, pan=0, freq=440, crunch=50, pulse=1.25, attack=0.005, sustain=1, decay=0.5, amp=0.25|
	var level, saw, reverb, pan2,fx;

	level = EnvGen.kr(Env([0,amp,amp,0], [attack,sustain,decay]), doneAction: 2);
	saw = Pulse.ar(freq, 0.5, Saw.kr(crunch, SinOsc.kr(pulse)));

	saw = tanh(saw * 2);
	saw = PitchShift.ar(saw, 0.2, SinOsc.kr(0.1).range(0.95, 1.05));

	fx = CombC.ar(saw, 0.3, LFNoise1.kr(0.5).range(0.01, 0.1), 3);
	reverb = FreeVerb.ar(saw + fx, 0.5, 1, 1);
	pan2 = Pan2.ar(reverb, pan);

	Out.ar(out, pan2 * level);
}.add;

// 启动音乐
Routine({
	Pbind(
		\instrument, \crystal_mist,
		\freq, Pstutter(Pseq([4], inf), Pseq([440, 330, 440, 275] * 0.618, inf)),
		\dur, Pseq([1], inf),
		\crunch, 20,
		\pulse, 10,
		\amp, 0.2
	).play;

	Pbind(
		\instrument, \crystal_mist,
		\freq, Pstutter(Pseq([4], inf), Pseq([440, 550, 440, 330] * 2, inf)),
		\dur, Pseq([0.5], inf),
		\crunch, 1,
		\pulse, 1.25,
		\amp, 0.2
	).play;
}).play;
)

// 2. 万花筒可视化部分 ================================================
(
var width = 600, height = 600;
var win = Window("Real-time Kaleidoscope", Rect(100, 100, width, height)).front;
var view = UserView(win, win.view.bounds).background_(Color.black);
var bufferSize = 512;
var data = Signal.newClear(bufferSize).fill(0);
var scopeBuf = Buffer.alloc(s, bufferSize);
var scopeSynth, updateRoutine;

// 更灵敏的音频分析器
SynthDef(\audioAnalyzer, { |bufnum|
    var in = In.ar(0, 2).mean; // 监听主输出
    var env = Amplitude.kr(in, 0.05, 0.2); // 包络跟随
    ScopeOut.ar(in * env.pow(0.5), bufnum); // 动态增强细节
}).add;

// 增强的绘制函数
view.drawFunc = {
    var center = view.bounds.center;
    var radius = min(center.x, center.y) * 0.85;
    var baseHue = Main.elapsedTime.frac * 0.3; // 缓慢变化的基色

    6.do { |petal|
        var rotation = petal * (2pi/6);
        var hue = (baseHue + (petal/9)).wrap(0,1);

        Pen.strokeColor = Color.hsv(hue, 0.9, 1.0);
        Pen.width = 1.8;

        Pen.moveTo(
            center.x + (0 * cos(rotation) - 0 * sin(rotation)) @
            center.y + (0 * sin(rotation) + 0 * cos(rotation))
        );

        bufferSize.do { |i|
            var angle = i * (2pi/bufferSize);
            var mag = data[i].clip(0,1).pow(1.5) * radius * 1.6;
            var x = mag * cos(angle);
            var y = mag * sin(angle);

            var rotX = center.x + (x * cos(rotation) - y * sin(rotation));
            var rotY = center.y + (x * sin(rotation) + y * cos(rotation));

            Pen.lineTo(rotX @ rotY);
        };
        Pen.stroke;
    };
};

// 启动系统
Routine({
    s.sync; // 等待服务器
    scopeSynth = Synth(\audioAnalyzer, [\bufnum, scopeBuf], addAction: \addToTail);

    // 高响应度更新循环
    updateRoutine = Routine({
        loop {
            scopeBuf.getn(0, bufferSize, { |bufData|
                var newData = Signal.newFrom(bufData);
                // 动态压缩和增强
                data = newData.normalize(-1,1).abs
                    .blend(data, 0.15) // 保持部分平滑
                    .pow(1.2); // 增强小信号
            });
            (1/60).wait; // 60fps刷新
            { view.refresh }.defer; // 确保GUI更新
        };
    }).play(AppClock);

    // 窗口关闭时清理
    win.onClose = {
        updateRoutine.stop;
        scopeSynth.free;
        scopeBuf.free;
    };
}).play;
)