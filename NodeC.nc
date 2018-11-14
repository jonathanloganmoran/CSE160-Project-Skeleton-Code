/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 * LAST EDIT | P3: Reliable Transport and Congestion Control
 * @author jonathanloganmoran
 * @date   2018/11/13
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"
#include "includes/socket.h"					// wire for P3: Connection setup & teardown

configuration NodeC{
}
implementation {
    components MainC;
    components new TimerMilliC() as myTimerC;			// init timer (ms), testing neighbor discovery
    components new TimerMilliC() as ntimerC;			// P1: neighbor discovery routine
    components new TimerMilliC() as rtimerC;			// P2: route updating routine
    components new TimerMilliC() as ctimerC;			// P3: connection setup/teardown routine
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    /* init P2: DVR table updating */
    components new ListC(neighbor, 64) as nListC;		// P2: ([neighbor], [max # nexthop entries])
    components new ListC(neighbor, 64) as nRefresherC;		// P2: catch nexthop cost updates
    components new ListC(pack, 64) as prevPacksC;		// P2: neighbor routes, split horizon updating
    components new ListC(route, 64) as routeTableC;		// P2: global routes, poison reverse
    components new ListC(route, 64) as forwardTableC;		// P2: nexthop cost updates

    /* init P3: socket data stores */
    components new ListC(socket_port_t, MAX_NUM_OF_SOCKETS) as socketC;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    Node.periodicTimer->myTimerC;				// wire to component
    Node.nList->nListC;						// initialize instance
 
    /* wire route tables for P2: DVR */
    Node.nRefresher->nRefresherC;				// P2: neighbor update table
    Node.prevPacks->prevPacksC;					// P2: wire route update tables
    Node.routeTable->routeTableC;				// P2: routing table
    Node.forwardTable->forwardTableC;				// P2: nexthop cost updating

    /* wire sockets for P3: TCP */
    Node.socket->socketC;					// P3: connection setup & teardown

    /* wire timers for P2: DVR */
    Node.ntimer->ntimerC;					// P2: neighbor refresh routine
    Node.rtimer->rtimerC;					// P2: route update routing

    /* wire timers for P3: TCP */
    Node.ctimer->ctimerC;					// P3: connection setup/teardown routine
}
