/*
 * Copyright (c) 2016 Wilhansen Li. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
       * Redistributions of source code must retain the above copyright
         notice, this list of conditions and the following disclaimer.
       * Redistributions in binary form must reproduce the above
         copyright notice, this list of conditions and the following
         disclaimer in the documentation and/or other materials provided
         with the distribution.
       * Neither the name of Wilhansen Li nor the names of its
         contributors may be used to endorse or promote products derived
         from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
 * IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <iostream>
#include <fstream>
#include <sstream>
#include <cstdint>
#include <string>
#include <cstdio>
#include <vector>

#include <arpa/inet.h>

using namespace std;

#define AML_DT_HEADER 0x5f4c4d41
#define DT_HEADER_MAGIC		 0xedfe0dd0
#define AML_DT_ID_VARI_TOTAL		3

#pragma pack(push, 1)
struct DTHeader {
	uint32_t     magic;                  /* magic word of OF_DT_HEADER */
	uint32_t     totalsize;              /* total size of DT block */
};
struct Header {
	uint32_t magic;
	uint32_t version;
	uint32_t entry_count;	
};

template<unsigned int ID_SIZE=4>
struct HeaderEntry {
	char soc[ID_SIZE];
	char plat[ID_SIZE];
	char vari[ID_SIZE];
	uint32_t offset;
	char padding[4];
};
#pragma pack(pop)

typedef HeaderEntry<4> HeaderEntryV1;
typedef HeaderEntry<16> HeaderEntryV2;

void trimSpace(char *b, const int len) {
	int len2 = len;
	while (len2 > 0 && isspace(b[len2 - 1])) {
		len2--;
	}
	if (len2 < len && len2 > 0) {
		b[len2] = 0;
		b[len - 1] = 0;
	}
}
uint32_t swap_bytes_u32(uint32_t b) {
    return ((b & 0xFF000000) >> 24) |
           ((b & 0x00FF0000) >> 8) |
           ((b & 0x0000FF00) << 8) |
           (b << 24);
}
template<unsigned int ID_SIZE>
void dumpData(const uint32_t entries, const string &dest, ifstream &dtb) {
	typedef HeaderEntry<ID_SIZE> HeaderType;

	vector<HeaderType> headers;
	for ( uint32_t i = 0; i < entries; ++i ) {
		HeaderType h;
		dtb.read((char*)&h, sizeof(h));
	
		headers.push_back(h);
	}
	for ( uint32_t i = 0; i < headers.size(); ++i ) {
		auto &h = headers[i];
		ostringstream id;
		
		auto u32soc = reinterpret_cast<uint32_t*>(h.soc);
		auto u32plat = reinterpret_cast<uint32_t*>(h.plat);
		auto u32vari = reinterpret_cast<uint32_t*>(h.vari);
		for ( uint32_t j = 0; j < ID_SIZE/sizeof(uint32_t); ++j ) {
			*(u32soc + j) = swap_bytes_u32(*(u32soc + j));
			*(u32plat + j) = swap_bytes_u32(*(u32plat + j));
			*(u32vari + j) = swap_bytes_u32(*(u32vari + j));
		}
		trimSpace(h.soc, ID_SIZE);
		trimSpace(h.plat, ID_SIZE);
		trimSpace(h.vari, ID_SIZE);

		if ( h.soc[ID_SIZE-1] == 0 ) {
			id << h.soc;
		} else {
			id.write(h.soc, sizeof(h.soc));
		}
		id << '-';
		if ( h.plat[ID_SIZE-1] == 0 ) {
			id << h.plat;
		} else {
			id.write(h.plat, sizeof(h.plat));
		}
		id << '-';
		if ( h.vari[ID_SIZE-1] == 0 ) {
			id << h.vari;
		} else {
			id.write(h.vari, sizeof(h.vari));
		}
		cout << "Found header: " << id.str() << '\n';
		
		dtb.seekg(h.offset);
		DTHeader dtheader;
		dtb.read((char*)&dtheader, sizeof(dtheader));
		if ( dtheader.magic != DT_HEADER_MAGIC ) {
			cout.setf(ios::hex);
			cout << "\tDTB Header mismatch. Found: " <<  dtheader.magic;
			continue;
		}
		dtheader.totalsize = ntohl(dtheader.totalsize);
		cout.setf(ios::dec);
		cout << "\t offset: " << h.offset << " size: " << dtheader.totalsize << '\n';
		dtb.seekg(h.offset);
		vector<char> data(dtheader.totalsize);
		dtb.read(data.data(), data.size());
		ofstream output(dest + id.str() + ".dtb", ios::binary);
		output.write(data.data(), data.size());
	}
}

int main(int argc, char **argv) {
	if ( argc < 3  ) {
		cerr << "Usage: " << argv[0] << " boot.img out_prefix\n";
		return 1;
	}

	ifstream dtb(argv[1], ios::binary);
	if ( !dtb ) {
		cerr << "Unable to open dtb file: " << argv[2] << endl;
		return 1;
	}
	string dest;
	if ( argc > 2 ) {
		dest = argv[2];
	}
	Header header;
	dtb.read((char*)&header, sizeof(header));

	if ( header.magic != AML_DT_HEADER ) {
		cerr << "Invalid AML DTB header." << endl;
		return 1;
	}
	cout << "DTB Version: " << header.version << " entries: " << header.entry_count << endl;

	if(header.version == 1) {
		dumpData<4>(header.entry_count, dest, dtb);
	} else if(header.version == 2) {
		dumpData<16>(header.entry_count, dest, dtb);
	} else {
		cerr << "Unrecognized DTB version" << endl;
		return 1;
	}

	return 0;
}