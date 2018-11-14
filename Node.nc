/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
<<<<<<< Updated upstream
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/protocol.h"
=======

/* [Project #3: Reliable Transport and Congestion Control]
 * 
 * last edited:
 * @date         2018/11/13
 * @author       jonathanloganmoran
 *
 */


#include <Timer.h>					// P3: new TCP timer
#include "includes/command.h"
#include "includes/packet.h"				// P2: modified neighbor struct
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/protocol.h"				// P2: new routing protocols
#include "includes/socket.h"
>>>>>>> Stashed changes

module Node{
   uses interface Boot;
   

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

<<<<<<< Updated upstream
   uses interface CommandHandler;

   uses interface List<neighbor> as nList;	  // for neighbor List structure
   uses interface Timer<TMilli> as periodicTimer; // for controlled neighbor discovery
=======
    uses interface CommandHandler;		     	// P2: added routing table calls
    uses interface Timer<TMilli> as periodicTimer;

    /* wire from NodeC.nc for P2: neighbor discovery */
    uses interface List<neighbor> as nList;          	// P2: next-hop list
    uses interface List<neighbor> as nRefresher;     	// P2: periodic updates	 
    uses interface Timer<TMilli> as ntimer;	     	// P2: neighbor refresh routine

    /* wire from NodeC.nc for P2: DVR-RIP */
    uses interface List<pack> as prevPacks;	     	// P2: prevents ping echoing
    uses interface List<route> as routeTable;	     	// P2: next-hop global routing
    uses interface List<route> as forwardTable;	     	// P2: next-hop neighbor routes
    uses interface Timer<TMilli> as rtimer; 	     	// P2: force updates every 20s

    /* wire from NodeC.nc for P3: TCP */
    uses interface List<socket> as socket;		// P3: connection setup/teardown
>>>>>>> Stashed changes
}

implementation{
<<<<<<< Updated upstream
   pack sendPackage;
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   // neighbor n = {TOS_NODE_ID} 
   uint16_t currSeq = 0; 	// num of packets created vs forwarded 

   event void Boot.booted(){	// used to run interfaces
      call AMControl.start();
      
      call periodicTimer.startPeriodic(200000);		// run for 200,0000 (?), optimal for neighbor list refresh
      dbg(NEIGHBOR_CHANNEL, "Timer initiated! \n");
      dbg(GENERAL_CHANNEL, "Booted\n");
   }
=======
    pack sendPackage;
    
    /* sequence variable for deterministic routing */
    uint16_t curr_seq = 0;

    /* prototype of pack contents */
    void makePack(pack *Package, 
        uint16_t src, 
        uint16_t dest, 
        uint16_t TTL, 
        uint16_t Protocol, 
	uint16_t seq, 
	uint8_t *payload, 
	uint8_t length);

    event void Boot.booted(){	// used to run interfaces
        call AMControl.start();

        /* start neighbor discovery + routing routines */
        call ntimer.startPeriodic(200000);
        call rtimer.startPeriodic(200000);
        dbg(NEIGHBOR_CHANNEL, "Timer initiated! \n");
        dbg(GENERAL_CHANNEL, "Booted\n");
    }
>>>>>>> Stashed changes

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){ 
	dbg(GENERAL_CHANNEL, "Radio On\n");
      } 
      else {
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event void periodicTimer.fired() {
       /* remove neighbors from node's list
        * run every ~200,000
        * send out two packets, one with ping to nearest neighbor, other with pingreply to reach sender
        * catch when ping == pingreply and dest == tos_node_id
        * MOVE BELOW AMCONTROL IMPLEMENTATION
        */
        uint16_t i = 0;                         // initializing index variable for neighbor list
        uint16_t size = call nList.size();        // fetch current node list size

        for(i = 0; i < size; i++) {
            call nList.popback();               // remove each node from list
        }
<<<<<<< Updated upstream
	// request for new neighbors
        // rebroadcast, src= TOS_NODE_ID, dest= TOS_NODE_ID, set TTL to MAX_TLL, protocol=10, seq=0, payload
        makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, MAX_TTL, NEIGHBOR_REQUEST, 0, "neighbor command", PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);       // send neighbor request to nearest neighbors, wait for NEIGHBOR_RECIEVE
   }
=======

        /* compare rRefresher with nList to update route metrics */
	empty = call nRefresher.isEmpty();
	
	while(!empty) {
	    nr = call nRefresher.popfront();		// return + remove route
	    found = FALSE;				// initialize recog. route flag

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
	
        /* get size of neighbor routing tables */
	nsize = call nList.size();
	fsize = call forwardTable.size();
	rsize = call routeTable.size();
	
	/* handle forwarding updates */
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
>>>>>>> Stashed changes

	for(i = 0; i < fsize; i++) {	
	    r = call forwardTable.popfront();		// pull all intermediate routes
	    found = FALSE;
    	
            for(j = 0; j < nsize; j++) {		// check against neighbor list
                n = call nList.get(j);			// get neighbor from nList
		   					// check if entries match
                if(r.dest == n.id && r.next == n.id) {
		    found = TRUE;			
		    call forwardTable.pushback(r);  // put back if same	
	    	    j = nsize;			// break loop
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
    event void ctimer.fired() {
        // handle connection setup/teardown
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

        dbg(GENERAL_CHANNEL, "Packet Received\n");

        if(len==sizeof(pack)) {	// store pack if allocated size is enough
        pack* myMsg=(pack*) payload;	// cast as pack type
        //dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload); // broadcast contained message
	  

	/* handle neighbor discovery request */
	if(myMsg->protocol == NEIGHBOR_REQUEST) {	// read packet from neighbor (protocol 10 == neighbor request)
              //dbg(NEIGHBOR_CHANNEL, "Neighbor request initiated");
	      // set src = TOS_NODE_ID, dest = myMsg->dest, change protocol to 11 == neighbor recieve
	      makePack(&sendPackage, TOS_NODE_ID, myMsg->dest, myMsg->TTL-1, NEIGHBOR_RECIEVE, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
	      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
	      return msg;
          }
	  
	if(myMsg->protocol == NEIGHBOR_REPLY) {	// recieved packet from neighbor
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

	/* [Project #2]: distance vector routing
	 * handle routing table routine
	 * debug(ROUTING_CHANNEL, "route update recieved \n");
         */
	if(myMsg->protocol == PROTOCOL_ROUTEUPDATE) {
	    route r;
	    route *rp;
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
			    /* Task 2.3: Split Horizon-Poison Reverse, init cost as "infinity" */
			    rp->cost = INFINITE_COST;
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
			PRTOCOL_ROUTEUPDATE, curr_seq, "route update" PACKET_MAX_PAYLOAD_SIZE);

			neighborBroadcast(myMsg->src);
			curr_seq++;

		    return msg;
		    }
		    /* identify best cost route */	
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
	    /* create new route */
	    r.dest = myMsg->dest;
	    r.next = myMsg->src;
	    r.cost = myMsg->TTL;
	    r.cost += 1;
	
	    /* push to global routing table */
	    call routeTable.pushfront(r);
	    makePack(&sendPackage, TOS_NODE_ID, r.dest, r.cost,
	    PROTOCOL_ROUTEUPDATE, curr_seq, "route update", PACKET_MAX_PAYLOAD_SIZE);

	    neighborBroadcast(myMsg->src);	//forward to neighbors
	    curr_seq++;
	}
	return msg;
    }

    /* [Project #1]: Flooding and Neighbor Discovery 
     * flood packets using AM_BROADCAST
     * handle circulation with TTL
     */
    if(myMsg->dest == TOS_NODE_ID) {
        // dbg(FLOODING_CHANNEL, "Packet recieved at destination: %d\n", myMsg->dest);
        // dbg(FLOODING_CHANNEL, "Package Payload: %s\n", myMsg->payload);
              
	if(myMsg->protocol == PROTOCOL_PING) {	// has not completed full RTT
	    //dbg(FLOODING_CHANNEL, "Packet one-way time (ms): TBA, TTL= %d\n", myMsg->TTL); 

	    // swap dest and src, set protocol to PROTOCOL_PINGREPLY
            makePack(&sendPackage, myMsg->dest, myMsg->src, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);

	    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
	    curr_seq++;			// packet is being echoed
	return msg;
	}
        else if(myMsg->protocol == PROTOCOL_PINGREPLY) {
	     // dbg(FLOODING_CHANNEL, "Packet has completed one RTT, TTL=  %d\n", myMsg->TTL);
             return msg;
	}
    return msg;
    }
    else {	// catch packet to determine if stale
	     // check if in previous known packlist
             // to be implemented in project #2
             if(myMsg->TTL > 0) { 
		 // repeat packet
	         makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
		 call Sender.send(sendPackage, AM_BROADCAST_ADDR);	// send to neighbors	
		 // push packet to node's packlist -- proj_2
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
        // set TTL= 8 to send packet from src = 1 to dest = 10
        // UPDATED: TTL = MAX_TTL to allow packet to circle back to src
        // UPDATED: currSeq = num of packets recieved at TOS_NODE_ID == src
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 0, currSeq, payload, PACKET_MAX_PAYLOAD_SIZE);
        // call Sender.send(sendPackage, destination);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR); //relay to nearby neighbors
        currSeq++;
   }

    event void CommandHandler.printNeighbors(){
        /* use list to store neighbor pairs */
        uint16_t i;
        neighbor node;				// initialize entries
        uint16_t size = call nList.size();	// size() returns num of neighbors in node list
        dbg(NEIGHBOR_CHANNEL, "Direct neighbors of %d are: \n", TOS_NODE_ID);
        for(i = 0; i < size; i++) {
            node = call nList.get(i);		// return neighbor_id list
            dbg(NEIGHBOR_CHANNEL, "%d\n", node.neighbor_id);
        }
   }
    
    event void CommandHandler.printRouteTable(){}

    event void CommandHandler.printLinkState(){}

    event void CommandHandler.printDistanceVector(){}

    event void CommandHandler.setTestServer(){}

    event void CommandHandler.setTestClient(){}

    event void CommandHandler.setAppServer(){}

    event void CommandHandler.setAppClient(){}

    event void CommandHandler.closeConnection(uint16_t dest, uint8_t srcPort, uint8_t destPort){}

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
       Package->src = src;
       Package->dest = dest;
       Package->TTL = TTL;
       Package->seq = seq;
       Package->protocol = protocol;
       memcpy(Package->payload, payload, length);
   }
}
