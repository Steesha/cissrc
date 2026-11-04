/*
  islzma.h, by Jordan Russell for Inno Setup
  This file is public domain (like the LZMA SDK)
*/

#ifndef INNO_ISLZMA_H
#define INNO_ISLZMA_H

#include "../../../../Components/Lzma2/LzmaEnc.h"
#include "../../../../Components/Lzma2/Lzma2Enc.h"

// Private definition of a handle; callers of the DLL should use void*
struct LZMAHandle {
	int marker;
	BoolInt LZMA2;
	CLzmaEncHandle encoder1;
	CLzma2EncHandle encoder2;
};

struct LZMAEncoderProps {
	int Algorithm;
	int BlockSize;
	int BTMode;
	int NumHashBytes;
	UInt32 DictionarySize;
	int NumBlockThreads;
	int NumFastBytes;
	int NumThreads;
	int NumThreadGroups;
};

SRes Z7_STDCALL LZMA_Init(BoolInt LZMA2, struct LZMAHandle **handle);
SRes Z7_STDCALL LZMA_SetProps(struct LZMAHandle *handle,
	struct LZMAEncoderProps *encProps, size_t encPropsSize);
SRes Z7_STDCALL LZMA_Encode(struct LZMAHandle *handle, ISeqInStream *inStream,
	ISeqOutStream *outStream, ICompressProgress *progress);
SRes Z7_STDCALL LZMA_End(struct LZMAHandle *handle);

#endif /* INNO_ISLZMA_H */
