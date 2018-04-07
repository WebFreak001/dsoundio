#!/usr/bin/env dub
/+ dub.sdl:
	name "sio-sine"

	dependency "dsoundio" path=".."
+/

import soundio.soundio;

import std.math;
import std.stdio;
import std.string;

struct Phase
{
	float left = 0.01f, right = 0.01f;
}

int main(string[] args)
{
	auto soundio = soundio_create();
	if (!soundio)
	{
		stderr.writeln("Out of memory");
		return 1;
	}
	scope (exit)
		soundio_destroy(soundio);

	if (auto err = soundio_connect(soundio))
	{
		stderr.writeln("Error connecting: ", soundio_strerror(err).fromStringz);
		return 1;
	}

	soundio_flush_events(soundio);

	int default_out_device_index = soundio_default_output_device_index(soundio);
	if (default_out_device_index < 0)
	{
		stderr.writeln("No output device found");
		return 1;
	}

	auto device = soundio_get_output_device(soundio, default_out_device_index);
	if (!device)
	{
		stderr.writeln("Out of memory");
		return 1;
	}
	scope (exit)
		soundio_device_unref(device);

	stderr.writeln("Output device: ", device.name.fromStringz);

	Phase phase;

	auto outstream = soundio_outstream_create(device);
	scope (exit)
		soundio_outstream_destroy(outstream);
	outstream.format = SoundIoFormatFloat32NE;
	outstream.userdata = &phase;
	outstream.write_callback = &write_callback;

	if (auto err = soundio_outstream_open(outstream))
	{
		stderr.writeln("Unable to open device: ", soundio_strerror(err).fromStringz);
		return 1;
	}

	if (outstream.layout_error)
		stderr.writeln("Unable to set channel layout: ",
				soundio_strerror(outstream.layout_error).fromStringz);

	if (auto err = soundio_outstream_start(outstream))
	{
		stderr.writeln("Unable to start device: ", soundio_strerror(err).fromStringz);
		return 1;
	}

	while (true)
		soundio_wait_events(soundio);
}

static const float PI = 3.1415926535f;
static float seconds_offset = 0.0f;
extern (C) static void write_callback(SoundIoOutStream* outstream,
		int frame_count_min, int frame_count_max)
{
	const SoundIoChannelLayout* layout = &outstream.layout;
	SoundIoChannelArea* areas;
	int frames_left = frame_count_max;
	Phase* phase = cast(Phase*) outstream.userdata;

	while (frames_left > 0)
	{
		int frame_count = frames_left;

		if (auto err = soundio_outstream_begin_write(outstream, &areas, &frame_count))
		{
			stderr.writeln(soundio_strerror(err).fromStringz);
			assert(false);
		}

		if (!frame_count)
			break;

		foreach (frame; 0 .. frame_count)
		{
			foreach (channel; 0 .. layout.channel_count)
			{
				float* ptr = cast(float*)(areas[channel].ptr + areas[channel].step * frame);
				*ptr = 0.5f * sin(phase.left);
			}
			phase.left *= 1.0001f;
		}

		if (auto err = soundio_outstream_end_write(outstream))
		{
			stderr.writeln(soundio_strerror(err).fromStringz);
			assert(false);
		}

		frames_left -= frame_count;
	}
}
