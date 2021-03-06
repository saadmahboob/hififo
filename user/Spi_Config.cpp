/*
 * HIFIFO: Harmon Instruments PCI Express to FIFO
 * Copyright (C) 2014 Harmon Instruments, LLC
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/
 */

#include <unistd.h>
#include <stdlib.h>
#include <iostream>
#include <stdexcept>
#include <vector>

#include "Spi_Config.h"

using namespace std;

SPI_Config::SPI_Config(Sequencer *sequencer, int addr)
{
	seq = sequencer;
	spi_address = addr;
	cout << "opened SPI_Config, addr = " << addr << "\n";
}

void SPI_Config::txrx(char * data, int len, int read_offset)
{
	for(int i=0; i<len; i++) {
		uint64_t d_next = 0xFF & data[i];
		if(len != i+1)
			d_next |= 0x100;
		seq->write_single(spi_address, d_next);
		seq->wait(360);
		if((read_offset >= 0) && (i >= read_offset))
			seq->read_req(1, spi_address);
	}
	if(read_offset < 0)
		return;
	std::vector<uint64_t> rdata64 = seq->read_multi(0, 0);
	for(int i=0; i<(len-read_offset); i++)
		data[i] = rdata64[i];
	return;
}
