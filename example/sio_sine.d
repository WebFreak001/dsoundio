#!/usr/bin/env dub
/+ dub.sdl:
	name "sio-sine"

	dependency "libsoundio" path=".."
+/

import soundio.soundio;

import std.math;
import std.stdio;
import std.string;

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

	auto outstream = soundio_outstream_create(device);
	scope (exit)
		soundio_outstream_destroy(outstream);
	outstream.format = SoundIoFormatFloat32NE;
	outstream.write_callback = &write_callback;

	if (auto err = soundio_outstream_open(outstream))
	{
		stderr.writeln("Unable to open device: ", soundio_strerror(err).fromStringz);
		return 1;
	}

	if (outstream.layout_error)
		stderr.writeln("Unable to set channel layout: ", soundio_strerror(outstream.layout_error).fromStringz);

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
extern(C) static void write_callback(SoundIoOutStream* outstream, int frame_count_min, int frame_count_max)
{
	const SoundIoChannelLayout* layout = &outstream.layout;
	float float_sample_rate = outstream.sample_rate;
	float seconds_per_frame = 1.0f / float_sample_rate;
	SoundIoChannelArea* areas;
	int frames_left = frame_count_max;

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

		float pitch = 440.0f;
		float radians_per_second = pitch * 2.0f * PI;
		for (int frame = 0; frame < frame_count; frame += 1)
		{
			float sample = sin((seconds_offset + frame * seconds_per_frame) * radians_per_second);
			for (int channel = 0; channel < layout.channel_count; channel += 1)
			{
				float* ptr = cast(float*)(areas[channel].ptr + areas[channel].step * frame);
				*ptr = sample;
			}
		}
		seconds_offset = fmod(seconds_offset + seconds_per_frame * frame_count, 1.0f);

		if (auto err = soundio_outstream_end_write(outstream))
		{
			stderr.writeln(soundio_strerror(err).fromStringz);
			assert(false);
		}

		frames_left -= frame_count;
	}
}
