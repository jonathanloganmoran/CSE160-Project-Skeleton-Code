//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: jonathanloganmoran
//$LastChangedDate: 2018-11-12 $
y
#ifndef PROTOCOL_H
#define PROTOCOL_H

//PROTOCOLS
enum{
	PROTOCOL_PING = 0,
	PROTOCOL_PINGREPLY = 1,
	PROTOCOL_LINKEDLIST = 2,
	PROTOCOL_NAME = 3,
	PROTOCOL_TCP= 4,		// P3: handle connection setup/teardown
	PROTOCOL_DV = 5,


	/* Project #2: DVR-RIP */
	PROTOCOL_NEIGHBORREQUEST = 10,	// P2: send packet to neighbors, wait for reply
	PROTOCOL_NEIGHBORRECEIVE = 11,	// P2: receive packet from neighbor, handle request
	PROTOCOL_ROUTEUPDATE = 12;	// P2: broadcast updated route

	/* Project #3: TCP */
	PROTOCOL_TCPDATA = 13;		// P3: init TCP window transfer
   PROTOCOL_CMD = 99
};



#endif /* PROTOCOL_H */
