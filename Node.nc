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
}

implementation{
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

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

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

      dbg(GENERAL_CHANNEL, "Packet Received\n");

      if(len==sizeof(pack)) {	// store pack if allocated size is enough
          pack* myMsg=(pack*) payload;	// cast as pack type
          dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload); // broadcast contained message
	  
          if(myMsg->dest == TOS_NODE_ID) {	// dest of packet has been reached
              dbg(FLOODING_CHANNEL, "Packet recieved at destination: %d\n", myMsg->dest);	// print destination node 
              dbg(FLOODING_CHANNEL, "Package Payload: %s\n", myMsg->payload);
              
	      if(myMsg->protocol == 0) {	// has not completed full RTT
	      // swap dest and src, set protocol to PROTOCOL_PINGREPLY
	      makePack(&sendPackage, myMsg->dest, myMsg->src, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
	      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
	      }

              return msg;
	  }
          else if(myMsg->src == TOS_NODE_ID) {  // packet returned to src node
	      dbg(FLOODING_CHANNEL, "Packet returned to source \n");	      

	      if(myMsg->protocol == 1) {		// packet has returned from dest
		  dbg(FLOODING_CHANNEL, "Packet has completed one RTT \n");
	      }

              return msg;
	  }
          else {	// catch packet to determine if stale
              if(myMsg->TTL > 0) { 
		  // repeat packet
	          makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
		  call Sender.send(sendPackage, AM_BROADCAST_ADDR);	// send to neighbors	
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
      // set TTL to 10 from 0
      makePack(&sendPackage, TOS_NODE_ID, destination, 10, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      // call Sender.send(sendPackage, destination);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR); //relay to nearby neighbors
   }

   event void CommandHandler.printNeighbors(){
       /* use list to store neighbor pairs */

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
