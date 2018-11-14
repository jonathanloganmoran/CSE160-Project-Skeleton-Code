//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: jonathanloganmoran $

#ifndef PACKET_H
#define PACKET_H


#include "protocol.h"
#include "channels.h"

enum{
	PACKET_HEADER_LENGTH = 8,
	PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH,
	MAX_TTL = 10				// initialize new packets to be MAX_TTL
	NEIGHBOR_LIFESPAN = 3;			// missed neighbor updates before assumed node death
	INFINITE_COST = 0;			// P2: poison reverse cost updates

	/* init P3: connection setup/teardown */
	MAX_TRANSMISSION_SIZE = 64;		// max packets transferrable in single TCP
	SYN = 1;				// P3: establish a connection (request)
	ACK = 2;				// P3: acknowledge receieved SYN packet (accept)
	FIN = 3;				// P3: connection teardown (close)

};

/* Project #1: neighbor discovery */
typedef nx_struct pack{
	nx_uint16_t dest;
	nx_uint16_t src;
	nx_uint16_t seq;			// P1: broadcast packets
	nx_uint8_t TTL;				// P1: wait for neighbors
	nx_uint8_t protocol;			// P1: ping/ping_reply
	nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}pack;

/* Project #2: DVR-RIP */
typedef nx_struct neighbor{			// P2: node struct
        nx_uint16_t id;				// P2: nexthop node
	nx_uint16_t TTL;			// P2: detect link death
}neighbor;

typedef nx_struct route{
	nx_uint16_t dest;			// P2: global node id
	nx_uint16_t next;			// P2: nexthop node id
	nx_uint8_t cost;			// P2: hop metrics
}route;

/* Project #3: TCP */
typedef nx_struct socket{

}socket;


/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input){
	dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol:%hhu  Payload: %s\n",
	input->src, input->dest, input->seq, input->TTL, input->protocol, input->payload);
}

enum{
	AM_PACK=6
};

#endif
