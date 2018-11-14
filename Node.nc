/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

/* [Project #3: Reliable Transport and Congestion Control]
 * @date           2018/11/13
 * @coauthor       jonathanloganmoran
 * @collaborator   wcrumpton
 *
 */

#include <Timer.h>					// P3: new TCP timer
#include "includes/command.h"
#include "includes/packet.h"				// P2: modified neighbor struct
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/protocol.h"				// P2: new routing protocols
#include "includes/socket.h"				// P3: connection setup

module Node{
    uses interface Boot;

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface CommandHandler;

    uses interface CommandHandler;		     	// P2: added routing table calls
    uses interface Timer<TMilli> as periodicTimer;

    /* wire from NodeC.nc for T2.1: neighbor discovery */
    uses interface List<neighbor> as nList;          	// P2: next-hop list
    uses interface List<neighbor> as nRefresher;     	// P2: periodic updates	 
    uses interface Timer<TMilli> as ntimer;	     	// P2: neighbor refresh routine

    /* wire from NodeC.nc for T2.2: DVR-RIP */
    uses interface List<pack> as prevPacks;	     	// P2: prevents ping echoing
    uses interface List<route> as routeTable;	     	// P2: next-hop global routing
    uses interface List<route> as forwardTable;	     	// P2: next-hop neighbor routes
    uses interface Timer<TMilli> as rtimer; 	     	// P2: force updates every 20s

    /* wire from NodeC.nc for P3.1: TCP */
    uses interface List<socket_store_t> as sockets;	// P3: connection setup/teardown
    uses interface Timer<TMilli> as ctimer;		// P3: establish connection routine

}

implementation{
    pack sendPackage;
 
    uint16_t curr_seq = 0;				// P1: deterministic routing
    void exclusiveBroadcast(uint16_t exception);	// P2: broadcast outward (avoid self-directed packets)
    void smartPing();					// P2:
    
    uint16_t nextPort = 0;				// P3: next port id

    /* prototype of pack contents */
    void makePack(pack *Package, 
        uint16_t src, 
        uint16_t dest, 
        uint16_t TTL, 
        uint16_t Protocol, 
	uint16_t seq, 
	uint8_t *payload, 
	uint8_t length);

    event void Boot.booted(){				// P3: init transport structure and TCP timer
        call AMControl.start();

	/* T3.1: connection setup and teardown */
        socketBoot();					// init socket.h struct

        /* P2: start neighbor discovery + routing routines */
        call ntimer.startPeriodic(200000);
        call rtimer.startPeriodic(200000);
	
        // dbg(NEIGHBOR_CHANNEL, "Timer initiated! \n");
        // dbg(GENERAL_CHANNEL, "Booted\n");
    }

    event void AMControl.startDone(error_t err){
        if(err == SUCCESS){ 
	// dbg(GENERAL_CHANNEL, "Radio On\n");
        } 
        else {
           // Retry until successful
           call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err){}

    /* Project #1: neighbor discovery */
    /* event void periodicTimer.fired() {
     *     run every ~200,000
     *     send out two packets, one with ping to nearest neighbor, other with pingreply to reach sender
     *     catch when ping == pingreply and dest == tos_node_id
     */

    /* Project #2: DVR-RIP */
    event void ntimer.fired() {				// NEW T2.1: neighbor discovery overhaul
	bool found;
	bool empty;
	neighbor n;
	neighbor* np;
	uint16_t i;
	uint16_t j;
	uint16_t nsize;
	uint16_t nrsize;
	nsize = call nList.size();
	nrsize = call nRefresher.size();

							// BEGIN T2.1: neighbor refresh routine
	for(i = 0; i < nsize; i++){			
	    np = call nList.getAddr(i);
	    np->TTL--;					// decrement TTL for incoming neighbor packets
	}

							// NEW intermediate route update handling
	empty = call nRefresher.isEmpty();

							// compare nRefresher with nList to update route metrics
	while(!empty) {
	    nr = call nRefresher.popfront();		// clear nRefresher node entry
	    found = FALSE;				// init update flag
	
	    for(j = 0; j < nsize; j++) {
	    	np = call nList.getAddr(j);		// return neighbor pointer
		if(np->id == n.id) { 			// previously found
		    np->TTL = NEIGHBOR_LIFESPAN;	// reset TTL
		    found = TRUE;			// flag recognized route
		    j = nsize;				// break loop
		}
	    }

	    if(found == FALSE) {			// neighbor not in nList
		nr.TTL = NEIGHBOR_LIFESPAN;		// reset TTL
		call nList.pushfront(nr);		// put new route in nList
            }

	    empty = call nRefresher.isEmpty();
	}

        for(i = 0; i < nsize; i++) {			// wipe missing neighbors from nList
	    n = call nList.popfront();			// pull neighbor
	    if(n.TTL < 0) {				// check if not stale
	        call nList.pushback(n);			// push to nList
	    }
	}

	//send refresh packet to all neighboring nodes
	makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, MAX_TTL, NEIGHBOR_REFRESH, currentSequence, "neighbor command", PACKET_MAX_PAYLOAD_SIZE);
	call Sender.send(sendPackage, AM_BROADCAST_ADDR);
       	curr_seq++;
    }

    event void rtimer.fired() {
	bool found;
	bool empty;
	neighbor n;
	route r;
	route *rp;
	uint16_t id;
	uint16_t i;
	uint16_t j;
	uint16_t fsize;
	uint16_t nsize;
        uint16_t risze;
	
        /* P2: get size of neighbor routing tables */
	nsize = call nList.size();
	fsize = call forwardTable.size();
	rsize = call routeTable.size();
	
	/* P2.3: handle forwarding updates */
        for(i = 0; i < nsize; i++) {
	    n = call nList.get(i);
	    found = FALSE;

	    /* check if found in forwardTable */
	    for(j = 0; j < fsize; j++) {
    		r = call forwardTable.get(j);
		if(r.dest == n.id) {
		    found = TRUE;			// exists in table
		    j = fsize;				// break loop
		}
	    }
	    if(found == FALSE) {			// does not exist in forwardTable
		r.dest = n.id;
		r.next = n.id;
		r.cost = 1;

		/* store change in routing tables */
		call forwardTable.pushback(r);
		call routeTable.pushback(r);

		/* update table size and rebroadcast */
		fsize = call forwardTable.size();
		makePack(&sendPackage, TOS_NODE_ID, n.id, 1, PROTOCOL_ROUTEUPDATE, curr_seq, "route update", PACKET_MAX_PAYLOAD_SIZE);
		
		/* using new method to limit circulation */
		neighborBroadcast(n.id);
		curr_seq++;
	    }
	}
							
	for(i = 0; i < fsize; i++) {			// NEW T2.2: next-hop cost updates
	    r = call forwardTable.popfront();		// pull all intermediate routes
	    found = FALSE;
    	
            for(j = 0; j < nsize; j++) {		// check against neighbor list
                n = call nList.get(j);			// get neighbor from nList
		   					// check if entries match
                if(r.dest == n.id && r.next == n.id) {
		    found = TRUE;			
		    call forwardTable.pushback(r);  	// put back if same	
	    	    j = nsize;				// break loop
		}
	    }
        }
	
	if(found == FALSE) {			// assume neighbor is dead
	/* T2.3: Split Horizon-Poison Reverse
            * set cost --> infinity
	    * dbg(ROUTING_CHANNEL, "Node %d has died\n", id);
	    */
	    for(j = 0; j < rsize; j++) {
	        rp = call routeTable.getAddr(j);
                if(rp->next == id) {
		    rp->cost = INFINITE_COST;	// initialized as int cost = 0
			/* node death -> broadcast route */
			makePack(&sendPackage, TOS_NODE_ID, rp->dest,
			INFINITE_COST, PROTOCOL_ROUTEUPDATE, curr_seq, 
			"route update", PACKET_MAX_PAYLOAD_SIZE);
		}	
	    }
	}
    }

    /* Project #3: Reliable Transport and Congestion Control */
    event void ctimer.fired() {				// NEW T3.1: handle connection setup/teardown (3000ms)
	uint8_t i;
	socket_store_t* socket;				// NEW T3.1: reference modified socket.h struct
	uint16_t size = call sockets.maxSize();		// NEW T3.1: store window buffers
	
	for(i = 0; i < size; i++) {
	    socket = call sockets.getAddr(i);		// get payload of each socket
	    if(socket->state == LISTEN) { }		// INIT T3.2: transmit advertisedwindows
	    if(socket->state == ESTABLISHED { }		// INIT T3.1: connection setup
	    if(socket->state == FIN) { }		// INIT T3.1: connection teardown
	}

    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

        dbg(GENERAL_CHANNEL, "Packet Received\n");

        if(len==sizeof(pack)) {	// store pack if allocated size is enough
        pack* myMsg=(pack*) payload;	// cast as pack type
        //dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload); // broadcast contained message
	  

	/* Project #1: handle neighbor discovery request */
	if(myMsg->protocol == PROTOCOL_NEIGHBORREQUEST) {	// read packet from neighbor (protocol 10 == neighbor request)
              //dbg(NEIGHBOR_CHANNEL, "Neighbor request initiated");
	      // set src = TOS_NODE_ID, dest = myMsg->dest, change protocol to 11 == neighbor recieve
	      makePack(&sendPackage, TOS_NODE_ID, myMsg->dest, myMsg->TTL-1, NEIGHBOR_RECIEVE, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
	      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
	      return msg;
          }
	  
	if(myMsg->protocol == PROTOCOL_NEIGHBORREPLY) {	// recieved packet from neighbor
            if(myMsg->dest == TOS_NODE_ID) {		// if intended dest
		//dbg(NEIGHBOR_CHANNEL, "Neighbor node identified. Packet from node %d\n, is neighbors with this node %d\n ", myMsg->dest, myMsg->src);
	      	// update node neighbor list
		neighbor n;				// then hold new neighbor
		n.id = myMsg->src;

		call nList.pushfront(node);		// and store into neighbor list
		return msg;
	    }
            return msg;					// else ignore if not a neighbor
	}

	/* Project #2: distance vector routing
	 * debug(ROUTING_CHANNEL, "route update recieved \n");
         */
	if(myMsg->protocol == PROTOCOL_ROUTEUPDATE) {
	    route r;
	    route* rp;
	    bool found = FALSE;
	    uint16_t i;
	    uint16_t j;
	    uint16_t size;
	    size = call routeTable.size();

	    /* ignore connected routes */
	    if(myMsg->dest == TOS_NODE_ID) {
	        return msg;
	    }
	    
	    for(i = 0; i < size; i++) {
	        rp = call routeTable.getAddr(i);
		if(myMsg->dest == rp->next) {
		    found = TRUE;
		    if(myMsg->src = rp->next) {    	// preferred route
		    	if(myMsg->TTL == INFINITE_COST) {
			    /* T2.3: Split Horizon-Poison Reverse */
			    rp->cost = INFINITE_COST;	// init cost as "infinity"
		    	}
		    	else {
			    /* update cost to neighbor */
			    rp->cost = myMsg->TTL;
			    rp->cost += 1;
		    }
		    makePack(&sendPackage, TOS_NODE_ID, rp->dest,
		    rp->cost, PROTOCOL_ROUTEUPDATE, curr_seq, 
		    "route update", PACKET_MAX_PAYLOAD_SIZE);
		    
		    /* T2.3: using new broadcast to reduce circulation */
		    neighborBroadcast(myMsg->src);
		    curr_seq++;

		return msg;
		}
		else {					// not shortest path
		    if(myMsg->TTL == INFINITE_COST) {    
			if(rp->cost == INFINITE_COST) {
			    return msg;			// ignore route
		        }
			makePack(&sendPackage, TOS_NODE_ID, rp->dest, 
			rp->cost, PROTOCOL_ROUTEUPDATE, curr_seq, 
			"route update", PACKET_MAX_PAYLOAD_SIZE);

			return msg;
		    }
		    if(rp->cost == INFINITE_COST) {	// path is down
			/* update cost of route to be infinity */
			rp->next = myMsg->src;
			rp->cost = myMsg->TTL;
			rp->cost += 1;

			makePack(&sendPackage, TOS_NODE_ID, rp->dest, dp->cost,
			PROTOCOL_ROUTEUPDATE, curr_seq, "route update" PACKET_MAX_PAYLOAD_SIZE);

			neighborBroadcast(myMsg->src);
			curr_seq++;

		    return msg;
		    }
		    /* T2.2: share best-cost route update*/	
		    if(myMsg->TTL+1 < rp->cost) {
			/* broadcast new route to neighbors */
			rp->next = myMsg->src;
			rp->cost = myMsg->TTL;
			rp->cost += 1;
			makePack(&sendPackage, TOS_NODE_ID, rp->dest, rp->cost,
			PROTOCOL_ROUTEUPDATE, curr_seq, "route update", PACKET_MAX_PAYLOAD_SIZE);
			
			neighborBroadcast(myMsg->src);
			curr_seq++;
		    return msg;
		    }
		}
	    }
        }
	if(!found) {
	    /* T2.2: create new route */
	    r.dest = myMsg->dest;
	    r.next = myMsg->src;
	    r.cost = myMsg->TTL;
	    r.cost += 1;
	
	    /* push to global routing table */
	    call routeTable.pushfront(r);
	    makePack(&sendPackage, TOS_NODE_ID, r.dest, r.cost,
	    PROTOCOL_ROUTEUPDATE, curr_seq, "route update", PACKET_MAX_PAYLOAD_SIZE);

	    neighborBroadcast(myMsg->src);				//forward to neighbors
	    curr_seq++;
	}
	return msg;
    }

    /* Project #3: TCP */
    if(myMsg->protocol == PROTOCOL_TCP) {
	if(myMsg->dest == TOS_NODE_ID) {
	    if(sizeof(myMsg->payload) == sizeof(TCP_PAYLOAD)) {	// size of control_package 
		TCP_PAYLOAD control = (TCP_PAYLOAD)myMsg->payload;	// valid package size
		if(control.flag == SYN) {				// T3.1: connection setup
		    // send SYN+ACK pack if server, else if data for client
		}
		if(control.flag == ACK) {				// T3.1: establish connection

		}

		if(control.flag == FIN) {				// T3.1: connection teardown

		}
    else {
	mackPack(&sendPackage, myMsg->src, myMsg->dest, myMsg->seq, myMsg->TTL-1, PROTOCOL_TCP, myMsg->seq, myMsg->payload, MAX_PAYLOAD_SIZE);
	smartPing();
    return msg;
    }

    /* Project #1: Flooding and Neighbor Discovery 
     * flood packets using AM_BROADCAST
     * handle circulation with TTL
     */
    if(myMsg->dest == TOS_NODE_ID) {
        // dbg(FLOODING_CHANNEL, "Packet recieved at destination: %d\n", myMsg->dest);
        // dbg(FLOODING_CHANNEL, "Package Payload: %s\n", myMsg->payload);
              
	if(myMsg->protocol == PROTOCOL_PING) {			// has not completed full RTT
	    //dbg(FLOODING_CHANNEL, "Packet one-way time (ms): TBA, TTL= %d\n", myMsg->TTL); 

	    // swap dest and src, set protocol to PROTOCOL_PINGREPLY
            makePack(&sendPackage, myMsg->dest, myMsg->src, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);

	    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
	    curr_seq++;						// packet is being echoed
	return msg;
	}
        else if(myMsg->protocol == PROTOCOL_PINGREPLY) {
	     // dbg(FLOODING_CHANNEL, "Packet has completed one RTT, TTL=  %d\n", myMsg->TTL);
             return msg;
	}
    return msg;
    }
    else {					// NEW T2.2: check if route exists in prevPacks list
        uint16_t i;
	uint16_t size = call prevPacks.size();
	pack prev;
	for(i = 0; i < size; i++) {		// NEW T2.2: check existance in table
	    prev = call prevPacks.get(i);
	    if(myMsg->src == prev.src && myMsg->src == prev.seq) {
		return msg;
	    }
	}
        if(myMsg->TTL > 0) {			// NEW T2.1: check remaining pings left 
	    // repeat packet
	    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
	    smartPing();			// NEW T2.1: ping neighboring
	    call prevPacks.pushfront(sendPackage);
            return msg;
	}
    return msg;
    }
	  // no packet shall pass
          return msg; 
      }

      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, currSeq, payload, PACKET_MAX_PAYLOAD_SIZE);

	smartPing();
        curr_seq++;
    }

    event void CommandHandler.printNeighbors(){
        /* use list to store neighbor pairs */
        uint16_t i;
        neighbor n;				// initialize entries
        uint16_t size = call nList.size();	// size() returns num of neighbors in node list
        dbg(NEIGHBOR_CHANNEL, "Direct neighbors of %d are: \n", TOS_NODE_ID);

        for(i = 0; i < size; i++) {
            n = call nList.get(i);		// return neighbor_id list
            dbg(NEIGHBOR_CHANNEL, "%d\n", node.neighbor_id);
        }
    }
    // T2.1: DVR 
    event void CommandHandler.printRouteTable(){
        uint16_t i;
	route r;
	uint16_t size = call routeTable.size();
	dbg(ROUTING_CHANNEL, "Routes of node %d include: \n", TOS_NODE_ID);
   	for (i=0; i< size; i++)	{
   	    r = call routeTable.get(i);
            if(r.cost == INFINITE_COST){ //if cost is infinite print it
  	        dbg(ROUTING_CHANNEL,  "dest: %d, next: %d, cost: infinity \n", r.dest, r.next);	
            }
	    else {
  	        dbg(ROUTING_CHANNEL,  "dest: %d, next: %d, cost: %d \n", r.dest, r.next, r.cost); //output the ID of the neighbor node
  	    }
    	}
    }

    event void CommandHandler.printLinkState(){}

    event void CommandHandler.printDistanceVector(){}

    // NEW T3.1: connection setup routine
    event void CommandHandler.setTestServer(){
        socket_store_t* socket;
	uint8_t socket_i = get_available_socket();
	socket = sockets.getAddr(socket_i);
	
	socket->src = port;
	call ctimer.startPeriodic(30000);
    }
    // NEW T3.1: establish connection
    event void CommandHandler.setTestClient(){
	socket_store_t* socket;
	uint8_t socket_index = get_available_socket();		
	socket = sockets.getAddr(socket_i);
	
	socket->src = srcPort;
	socket->dest.port = destPort;
	socket->dest.addr = dest;
	socket->transferSize = num;
	socket->totalSent = 0;
	
	//makePack(&sendPackage, TOS_NODE_ID, dest, 

    }

    event void CommandHandler.setAppServer(){}

    event void CommandHandler.setAppClient(){}

    event void CommandHandler.closeConnection(uint16_t dest, uint8_t srcPort, uint8_t destPort){
        TCP_PAYLOAD control;
	socket_store_t* socket = findSocket(srcPort);
	
	control.flag = FIN;
	control.srcPort = socket->src;
	control.destPort = docket->dest;
	
        makePack(&sendPackage, TOS_NODE_ID, dest, MAX_TTL, PROTOCOL_TCP, curr_seq, (uint8_t)&control, sizeof(TCP_PAYLOAD));
	smartPing();
	curr_seq++;

	socket->state = CLOSED;
	socket->src = NULL;
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
       Package->src = src;
       Package->dest = dest;
       Package->TTL = TTL;
       Package->seq = seq;
       Package->protocol = protocol;
       memcpy(Package->payload, payload, length);
    }

    // NEW T2.1: broadcast updates to all neighbors but self
    void exclusiveBroadcast(uint16_t exception) {
	uint16_t i;
	uint16_t size;
	neighbor n;
	size = call nList.size();
	for(i = 0; i < size; i++) {
	    n = call nList.get(i);
	    if(n.id != exception) {
		call Sender.send(sendPackage, n.id);
	    }
	}
    }

    // NEW T2.2: send ping using DVR tables
    void smartPing() {	
	int rsize;
	int i;
	bool found;
	route r;

	if(call routeTable.isEmpty()) {
	    call Sender.send(sendPackage, AM_BROADCAST_ADDR);	// send all routes to neighbors
	return;
	}
	else {
	    rsize = call routeTable.size();
	    found = FALSE;
	    
	    for(i = 0; i < rsize; i++) {			// T2.2: scan nexthop routes
	        r = call routeTable.get(i);
		if(sendPackage.dest == r.dest) {
		    found == TRUE;
		    if(r.cost == INFINITE_COST) {		// node death!
		        dbg(ROUTE_CHANNEL, "Node: %d has downed (packet dropped)\n", r.dest);
			return;
		    }
		}
		if(!found) {
		    call Sender.send(sendPackage, AM_BROADCAST_ADDR);	// flood using network discovery
		    return;
		} 
	}

    // NEW T3.1: initialize socket struct to CLOSED
    void socketBoot() {
	uint8_t i = 0;
	socket_store_t* socket;
	uint16_t size = call sockets.maxSize();

	for(i = 0; i < size; i++) {
	    socket = call sockets.getAddr(i);
	    socket.state = CLOSED;
	}
    }

    // NEW T3.1: return index of first FINed socket
    uint8_t get_socket() {
	uint8_t i = 0;
	socket_store_t socket;
	uint16_t size = call sockets.maxSize();
	
	for(i = 0; i < size; i++) {
	    socket = call sockets.get(i);
	    if(socket.state == CLOSED) {
		return i;
	    }
	}
    }
    // NEW T3.1: returns index of socket with corresponding port id
    socket_store_t* findSocket(uint8_t port) {
        uint8_t i = 0;
	socket_store_t* socket;

        uint16_t size = call sockets.maxSize();
        for(i = 0; i < size; i++) {
     	    socket = call sockets.getAddr(i);
	    if(socket->src == port) {
	        return socket;		
	    }
        }
    }
}
