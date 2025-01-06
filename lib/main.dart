import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:fftea/fftea.dart';
import 'package:pitch_detector_dart/algorithm/pitch_algorithm.dart';
import 'package:pitch_detector_dart/algorithm/yin.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:pitch_detector_dart/pitch_detector_result.dart';
import 'package:pitchupdart/instrument_type.dart';
import 'package:pitchupdart/pitch_handler.dart';
import 'package:pitchupdart/pitch_result.dart';
import 'package:pitchupdart/tuning_status.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tuner App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlueAccent),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Mridangam Tuner'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late FlutterAudioCapture _audioCapture;
  late PitchDetector _detector;
  late PitchHandler _handler;

  bool isRecording = false;
  double? frequency;
  late FFT fft;
  var note = "";
  List<double> _previousMagnitudes = [];
  double _lastValidFrequency = 0;
  int _stableCount = 0;
  String? selected_shruti;
  final List<String> Shrutis = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  @override
  void initState() {
    super.initState();
    _audioCapture = FlutterAudioCapture();
    _detector = PitchDetector(
      44100, 1024
    );
    _initAudioCapture();
    fft = FFT(256); // Initialize FFT with buffer size 256

  }
  Future<void> _initAudioCapture() async {
    try {
      await _audioCapture.init();
    } catch (e) {
      print('Error initializing audio capture: $e');
    }
  }

  Future<void> _toggleRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission required')),
      );
      return;
    }
    setState(() {
      isRecording = !isRecording;
    });

    if (isRecording) {
      await _audioCapture.start(listner,
        (error) {
          print('Error: $error');
        },
        sampleRate: 44100, // sampleRate
        bufferSize: 4096,   // bufferSize
      );
    } else {
      await _audioCapture.stop();
    }
    setState(() {
      note = "";
    });
  }

  void listner(dynamic data){
    if (data is List<num>) {
      final buffer = data.map((e) => e.toDouble()).toList();
      var pitchBuffer = Float64List.fromList(data.cast<double>());
      final List<double> audioSample = pitchBuffer.toList();
      // apply hanning window to the audio sample
      // for (int i = 0; i < audioSample.length; i++) {
      //   audioSample[i] *= 0.5 * (1 - cos(2 * pi * i / (audioSample.length - 1)));
      // }
      if (isOnset(audioSample, 0.1)){
        final result = _detector.getPitch(audioSample);
        if (result.pitched){
          setState(() {
            frequency = result.pitch;
            note = frequencyToNote(frequency!);
          });
        }
      }
    }
  }

  double spectralFlux(List<double> prev, List<double> current) {
    return List.generate(prev.length, (i) => max(current[i] - prev[i], 0.0))
        .reduce((a, b) => a + b);
  }

  bool isOnset(List<double> buffer, double threshold) {
    double energy = buffer.map((x) => x*x).reduce((a, b) => a + b);
    return energy > threshold;
  }

  String frequencyToNote(double freq) {
    const notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    double a = 440; // frequency of A (common reference point)
    double c0 = a * pow(2, -4.75);
    if (freq < c0) {
      return 'Unknown';
    }
    int halfSteps = (12 * log(freq / c0) / log(2)).round();
    int octave = (halfSteps / 12).floor();
    int noteIndex = halfSteps % 12;
    return notes[noteIndex] + octave.toString();
  }


  @override
  void dispose() {
    _audioCapture.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              isRecording ? 'Recording...' : 'Press the button to start recording',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _toggleRecording,
              icon: Icon(isRecording ? Icons.stop : Icons.mic),
              label: Text(isRecording ? 'Stop Recording' : 'Start Recording'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 40),
            _buildReadingDisplay('Frequency', '${frequency?.toStringAsFixed(2) ?? "N/A"} Hz'),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingDisplay(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text('Select Shruti',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          ),
          const SizedBox(height: 4),
          DropdownButton<String>(
            hint: const Text('Shruti'),
            value: selected_shruti,
            onChanged: (String? value) {
              setState(() {
                selected_shruti = value;
              });
            },
            items: Shrutis.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            ),

          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Note',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            note.isNotEmpty ? note : 'N/A',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
