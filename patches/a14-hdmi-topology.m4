# SPDX-License-Identifier: BSD-3-Clause
# Copyright, Linaro Ltd, 2023
#
# Extended for the ASUS Zenbook A14 UX3407NA HDMI audio path.

include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')
#
# Stream SubGraph for MultiMedia Playback
#
#  ______________________________________________
# |               Sub Graph 1                    |
# | [WR_SH] -> [PCM DEC] -> [PCM CONV] -> [LOG]  |- Kcontrol
# |______________________________________________|
#

dnl Playback MultiMedia1 - internal speakers
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
	`S16_LE', 48000, 48000, 4, 4,
	0x00004001, 0x00004001, 0x00006001, `110000')

dnl Capture MultiMedia2 - internal microphones
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA2,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004003, 0x00004003, 0x00006020, `110000')

dnl Playback MultiMedia5 - built-in HDMI / DisplayPort RX 2
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA5,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004002, 0x00004002, 0x00006010, `110000')
#
# Device SubGraphs
#

dnl WSA playback - internal speakers
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-playback.m4, `WSA_CODEC_DMA_RX_0', WSA_CODEC_DMA_RX_0,
	`S16_LE', 48000, 48000, 2, 4,
	LPAIF_INTF_TYPE_WSA, CODEC_INTF_IDX_RX0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004005, 0x00004005, 0x00006050)

dnl VA capture - internal microphones
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `VA_CODEC_DMA_TX_0', VA_CODEC_DMA_TX_0,
	`S16_LE', 48000, 48000, 1, 4,
	LPAIF_INTF_TYPE_VA, CODEC_INTF_IDX_TX0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004018, 0x00004018, 0x00006180)

dnl Built-in HDMI playback on DisplayPort RX 2
DEVICE_SG_ADD(audioreach/subgraph-device-display-port-playback.m4, `DISPLAY_PORT_RX_2', DISPLAY_PORT_RX_2,
	`S16_LE', 48000, 48000, 2, 2,
	0, 0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004006, 0x00004006, 0x00006060, `DISPLAY_PORT_RX_2')

STREAM_DEVICE_PLAYBACK_MIXER(WSA_CODEC_DMA_RX_0, ``WSA_CODEC_DMA_RX_0'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_MIXER(DISPLAY_PORT_RX_2, ``DISPLAY_PORT_RX_2'', ``MultiMedia5'')

STREAM_DEVICE_PLAYBACK_ROUTE(WSA_CODEC_DMA_RX_0, ``WSA_CODEC_DMA_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'')
STREAM_DEVICE_PLAYBACK_ROUTE(DISPLAY_PORT_RX_2, ``DISPLAY_PORT_RX_2 Audio Mixer'', ``MultiMedia5, stream4.logger1'')

dnl Capture routing
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA2, ``VA_CODEC_DMA_TX_0'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA2, ``MultiMedia2 Mixer'', ``VA_CODEC_DMA_TX_0, device110.logger1'')
