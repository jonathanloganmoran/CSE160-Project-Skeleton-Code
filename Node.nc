/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/protocol.h"

module Node{
   uses interface Boot;
   

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface List<neighbor> as nList;	  // for neighbor List structure
   uses interface Timer<TMilli> as periodicTimer; // for controlled neighbor discovery
}

implementation{
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
	// request for new neighbors
        // rebroadcast, src= TOS_NODE_ID, dest= TOS_NODE_ID, set TTL to MAX_TLL, protocol=10, seq=0, payload
        makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, MAX_TTL, NEIGHBOR_REQUEST, 0, "neighbor command", PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);       // send neighbor request to nearest neighbors, wait for NEIGHBOR_RECIEVE
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
