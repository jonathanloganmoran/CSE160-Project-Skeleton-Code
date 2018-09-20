/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components TimerMilliC() as myTimerC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components new ListC(neighbor, 64) as nListC;		// neighbor = object type, 64 = max # of elements in list

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    

    Node.periodicTimer->myTimerC;	// wire to component
}
