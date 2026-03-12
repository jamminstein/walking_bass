// Engine_UprightBass
// physical-modeling upright bass for norns
//
// Karplus-Strong plucked string core
// + body resonance (modal filters)
// + finger/fret noise transient
// + sympathetic string vibration
// + variable bow/pluck excitation

Engine_UprightBass : CroneEngine {

  var <synths;
  var <voiceIdx = 0;
  var <numVoices = 6;

  // global params
  var <bodyTone   = 800;
  var <bodyMix    = 0.35;
  var <fingerAmt  = 0.15;
  var <sympathetic = 0.12;
  var <driftAmt   = 2.0;
  var <brightness  = 0.4;
  var <reverbMix  = 0.18;
  var <reverbRoom = 0.55;
  var <masterAmp  = 0.9;

  var <reverbSynth;
  var <reverbBus;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    reverbBus = Bus.audio(context.server, 2);
    synths = Array.newClear(numVoices);

    // ----- main voice: plucked string + body + finger noise -----
    SynthDef(\uprightVoice, {
      arg out=0, revOut=0,
          freq=110, amp=0.5, gate=1,
          decay=3.0, brightness=0.4,
          bodyTone=800, bodyMix=0.35,
          fingerAmt=0.15, sympathetic=0.12,
          driftAmt=2.0,
          articulation=0;  // 0=normal, 1=ghost, 2=dig, 3=staccato, 4=sing

      var exciter, string, body, finger, symp, sig, env, ampEnv;
      var driftLFO, driftedFreq, delayTime;
      var bodyFreqs, bodyAmps, bodyDecays;
      var noiseEnv, noiseSig;

      // -- pitch drift (simulates real intonation)
      driftLFO = LFNoise1.kr(
        LFNoise0.kr(0.3).range(0.2, 1.8)
      ) * driftAmt;
      driftedFreq = freq * (2 ** (driftLFO / 1200));
      delayTime = (1.0 / driftedFreq).clip(1/8000, 1/20);

      // -- exciter (pluck impulse shaped by articulation)
      exciter = Select.ar(articulation.round.clip(0, 4), [
        // 0: normal pluck
        PinkNoise.ar * EnvGen.ar(Env.perc(0.001, 0.012)) * 0.8
        + Impulse.ar(0) * 0.4,

        // 1: ghost note (soft, muted)
        BrownNoise.ar * EnvGen.ar(Env.perc(0.003, 0.008)) * 0.35,

        // 2: dig (aggressive pluck)
        WhiteNoise.ar * EnvGen.ar(Env.perc(0.0005, 0.018)) * 1.2
        + Impulse.ar(0) * 0.6,

        // 3: staccato (short, percussive)
        PinkNoise.ar * EnvGen.ar(Env.perc(0.001, 0.006)) * 0.7
        + Impulse.ar(0) * 0.5,

        // 4: sing (bowed-ish, sustained excitation)
        LPF.ar(PinkNoise.ar, freq * 3) * 0.15
        * EnvGen.ar(Env.adsr(0.08, 0.1, 0.25, 0.3), gate)
      ]);

      // -- Karplus-Strong string model
      string = CombL.ar(exciter, 1/20, delayTime, decay * brightness.linlin(0, 1, 1.5, 0.6));
      // damping filter (lower brightness = more muffled)
      string = LPF.ar(string, freq * brightness.linexp(0, 1, 2.5, 12));
      // additional string color
      string = LeakDC.ar(string);
      string = HPF.ar(string, 35); // remove DC rumble

      // -- body resonance (3 modal resonances like a bass body)
      bodyFreqs = [bodyTone * 0.7, bodyTone, bodyTone * 1.55];
      bodyAmps  = [0.3, 0.45, 0.15];
      bodyDecays = [0.12, 0.08, 0.06];
      body = Mix.fill(3, { arg i;
        Ringz.ar(string, bodyFreqs[i].clip(60, 4000), bodyDecays[i]) * bodyAmps[i]
      });
      body = body.tanh * 0.6; // soft saturation

      // -- finger noise (string scrape / fret buzz transient)
      noiseEnv = EnvGen.ar(Env.perc(0.0005, 0.02 + (fingerAmt * 0.03)));
      noiseSig = HPF.ar(
        BPF.ar(WhiteNoise.ar, freq.linlin(40, 200, 2800, 4500), 0.3),
        1200
      ) * noiseEnv * fingerAmt * 3;

      // -- sympathetic string vibration (ghost harmonics)
      symp = Mix([
        SinOsc.ar(driftedFreq * 2, 0, 0.03),
        SinOsc.ar(driftedFreq * 3, 0, 0.015),
        SinOsc.ar(driftedFreq * 0.5, 0, 0.02),
      ]) * EnvGen.ar(Env.perc(0.05, decay * 0.6)) * sympathetic;

      // -- amplitude envelope
      ampEnv = Select.kr(articulation.round.clip(0, 4), [
        EnvGen.kr(Env.perc(0.003, decay), doneAction: Done.freeSelf),        // normal
        EnvGen.kr(Env.perc(0.005, decay * 0.4), doneAction: Done.freeSelf),  // ghost
        EnvGen.kr(Env.perc(0.001, decay * 1.1), doneAction: Done.freeSelf),  // dig
        EnvGen.kr(Env.perc(0.002, decay * 0.25), doneAction: Done.freeSelf), // staccato
        EnvGen.kr(Env.adsr(0.05, 0.2, 0.6, 0.8), gate, doneAction: Done.freeSelf), // sing
      ]);

      // -- mix it all together
      sig = (string * (1 - bodyMix)) + (body * bodyMix) + noiseSig + symp;
      sig = sig * ampEnv * amp;
      sig = sig.softclip;

      // -- stereo image (subtle)
      sig = [
        sig + (symp * 0.1),
        DelayN.ar(sig, 0.001, 0.0003 + LFNoise1.kr(2).range(0, 0.0004))
      ];

      Out.ar(out, sig);
      Out.ar(revOut, sig * 0.3);
    }).add;

    // ----- reverb tail (room ambience) -----
    SynthDef(\uprightReverb, {
      arg in=0, out=0, mix=0.18, room=0.55, damp=0.6;
      var sig, wet;
      sig = In.ar(in, 2);
      wet = FreeVerb2.ar(sig[0], sig[1], mix, room, damp);
      Out.ar(out, wet);
    }).add;

    // ----- click voice for count-in -----
    SynthDef(\uprightClick, {
      arg out=0, freq=1200, amp=0.4;
      var sig, env;
      env = EnvGen.ar(Env.perc(0.0005, 0.05), doneAction: Done.freeSelf);
      sig = SinOsc.ar(freq) * env * amp;
      sig = HPF.ar(sig, 600);
      Out.ar(out, sig ! 2);
    }).add;

    context.server.sync;

    // start reverb
    reverbSynth = Synth(\uprightReverb, [
      \in, reverbBus, \out, context.out_b, \mix, reverbMix, \room, reverbRoom
    ], context.xg, \addToTail);

    // ===== COMMANDS =====

    // note trigger: freq, amp, decay, articulation(0-4)
    this.addCommand("note", "fffi", { arg msg;
      var freq = msg[1], amp = msg[2], decay = msg[3], artic = msg[4];
      if(synths[voiceIdx].notNil) {
        synths[voiceIdx].set(\gate, 0);
      };
      synths[voiceIdx] = Synth(\uprightVoice, [
        \out, context.out_b,
        \revOut, reverbBus,
        \freq, freq,
        \amp, amp,
        \decay, decay,
        \brightness, brightness,
        \bodyTone, bodyTone,
        \bodyMix, bodyMix,
        \fingerAmt, fingerAmt,
        \sympathetic, sympathetic,
        \driftAmt, driftAmt,
        \articulation, artic
      ], context.xg);
      voiceIdx = (voiceIdx + 1) % numVoices;
    });

    // release a specific voice (for sustained "sing" articulation)
    this.addCommand("noteOff", "i", { arg msg;
      var idx = msg[1] % numVoices;
      if(synths[idx].notNil) {
        synths[idx].set(\gate, 0);
      };
    });

    // click for count-in
    this.addCommand("click", "ff", { arg msg;
      Synth(\uprightClick, [\out, context.out_b, \freq, msg[1], \amp, msg[2]], context.xg);
    });

    // --- global param commands ---
    this.addCommand("body_tone", "f", { arg msg;
      bodyTone = msg[1];
      synths.do({ arg s; if(s.notNil) { s.set(\bodyTone, msg[1]) } });
    });
    this.addCommand("body_mix", "f", { arg msg;
      bodyMix = msg[1];
      synths.do({ arg s; if(s.notNil) { s.set(\bodyMix, msg[1]) } });
    });
    this.addCommand("finger_amt", "f", { arg msg;
      fingerAmt = msg[1];
      synths.do({ arg s; if(s.notNil) { s.set(\fingerAmt, msg[1]) } });
    });
    this.addCommand("sympathetic_amt", "f", { arg msg;
      sympathetic = msg[1];
      synths.do({ arg s; if(s.notNil) { s.set(\sympathetic, msg[1]) } });
    });
    this.addCommand("drift_amt", "f", { arg msg;
      driftAmt = msg[1];
      synths.do({ arg s; if(s.notNil) { s.set(\driftAmt, msg[1]) } });
    });
    this.addCommand("brightness_amt", "f", { arg msg;
      brightness = msg[1];
      synths.do({ arg s; if(s.notNil) { s.set(\brightness, msg[1]) } });
    });
    this.addCommand("reverb_mix", "f", { arg msg;
      reverbMix = msg[1];
      reverbSynth.set(\mix, msg[1]);
    });
    this.addCommand("reverb_room", "f", { arg msg;
      reverbRoom = msg[1];
      reverbSynth.set(\room, msg[1]);
    });
    this.addCommand("master_amp", "f", { arg msg;
      masterAmp = msg[1];
    });
  }

  free {
    synths.do({ arg s; if(s.notNil) { s.free } });
    if(reverbSynth.notNil) { reverbSynth.free };
    if(reverbBus.notNil) { reverbBus.free };
  }
}
