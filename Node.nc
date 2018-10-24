/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 * 
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

/* [Project #2: Distance Vector Routing]
 * 
 * last edited:
 * @date         2018/10/24
 * @author       jonathanloganmoran
 *
 */


#include <Timer.h>			// new timers
#include "includes/command.h"
#include "includes/packet.h"		// modified neighbor struct
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/protocol.h"		// new routing protocols

module Node{
    uses interface Boot;
   

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface CommandHandler;	// added routing table calls
    uses interface Timer<TMilli> as periodicTimer;

    /* wire from NodeC.nc for neighbor discovery */
    uses interface List<neighbor> as nList;          // next-hop list
    uses interface List<neighbor> as nRefresher;     // periodic updates	 
    uses interface Timer<TMilli> as ntimer;	     // neighbor refresh routine

    /* wire from NodeC.nc for DVR-RIP */
    uses interface List<pack> as prevPacks;	     // prevents ping echoing
    uses interface List<route> as routeTable;	     // next-hop global routing
    uses interface List<route> as forwardTable;	     // next-hop neighbor routes
    uses interface Timer<TMilli> as rtimer; 	     // force updates every 20s
}


implementation{
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

    /* implement neighbor refresh routine every 200s */
    event void ntimer.fired() {
        bool found;
	bool empty;
	neighbor n;
	neighbor nr;
	neighbor* np;
	uint16_t i;
	uint16_t j;
	uint16_t nsize;
	uint16_t nrsize;
	nsize = call nList.size();
	nrsize = call nRefresher.size();
	
    /* Project #2: Task 1 -- Neighbor Discovery
         * neighbor refresh routine
         * channel: dbg(NEIGHBOR_CHANNEL, "nList refresh routine %d. . .", TOS_NODE_ID);
         */

        for(i = 0; i < nsize; i++) { 			// for all neighbors
            np = call nList.getAddr(i);			// get nList pack
            np->TTL--;					// and reduce TTL
        }

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

	//send refresh packet
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
		    found = TRUE;		// exists in table
		    j = fsize;			// break loop
		}
	    }
	    if(found == FALSE) {		// does not exist in forwardTable
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

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

      dbg(GENERAL_CHANNEL, "Packet Received\n");

      if(len==sizeof(pack)) {	// store pack if allocated size is enough
          pack* myMsg=(pack*) payload;	// cast as pack type
          //dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload); // broadcast contained message
	  

	  // HANDLE NEIGHBOR DISCOVERY
	  if(myMsg->protocol == NEIGHBOR_REQUEST) {	// read packet from neighbor (protocol 10 == neighbor request)
              //dbg(NEIGHBOR_CHANNEL, "Neighbor request initiated");
	      // set src = TOS_NODE_ID, dest = myMsg->dest, change protocol to 11 == neighbor recieve
	      makePack(&sendPackage, TOS_NODE_ID, myMsg->dest, myMsg->TTL-1, NEIGHBOR_RECIEVE, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
	      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
	      return msg;
          }
	  
	  if(myMsg->protocol == NEIGHBOR_RECIEVE) {	// recieved packet from neighbor
              if(myMsg->dest == TOS_NODE_ID) {
		  //dbg(NEIGHBOR_CHANNEL, "Neighbor node identified. Packet from node %d\n, is neighbors with this node %d\n ", myMsg->dest, myMsg->src);
	      	  // update node neighbor list
		  neighbor node;			// contains identifier of connected node
		  node.neighbor_id = myMsg->src;
		  call nList.pushfront(node);		// add to list struct
		  return msg;
	      }
              return msg;				// ignore if not a neighbor
	  }

	  // HANDLE FLOODING
	  if(myMsg->dest == TOS_NODE_ID) {
             // dbg(FLOODING_CHANNEL, "Packet recieved at destination: %d\n", myMsg->dest);
             // dbg(FLOODING_CHANNEL, "Package Payload: %s\n", myMsg->payload);
              
	      if(myMsg->protocol == 0) {	// has not completed full RTT
	          //dbg(FLOODING_CHANNEL, "Packet one-way time (ms): TBA, TTL= %d\n", myMsg->TTL); 
	          // swap dest and src, set protocol to PROTOCOL_PINGREPLY
	          makePack(&sendPackage, myMsg->dest, myMsg->src, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
	          call Sender.send(sendPackage, AM_BROADCAST_ADDR);
		  currSeq++;			// packet is being echoed
		  return msg;
	      }
              // else ping reply recieved
	  }
          else if(myMsg->src == TOS_NODE_ID) {
	      // dbg(FLOODING_CHANNEL, "Packet returned to source \n");	      

	      if(myMsg->protocol == 1) {
	      // dbg(FLOODING_CHANNEL, "Packet has completed one RTT, TTL=  %d\n", myMsg->TTL);
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

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
