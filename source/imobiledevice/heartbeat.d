/**
 * @file libimobiledevice/heartbeat.h
 * @brief Manage provisioning profiles.
 * \internal
 *
 * Copyright (c) 2013-2014 Martin Szulecki All Rights Reserved.
 * Copyright (c) 2012 Nikias Bassen All Rights Reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

module imobiledevice.heartbeat;

import plist.c: plist_t;

import imobiledevice.libimobiledevice;
import imobiledevice.lockdown;

import dynamicloader;

mixin makeBindings;
@libimobiledevice extern(C):

/** Service identifier passed to lockdownd_start_service() to start the heartbeat service */
enum HEARTBEAT_SERVICE_NAME = "com.apple.mobile.heartbeat";

/** Error Codes */
enum heartbeat_error_t
{
    HEARTBEAT_E_SUCCESS         =  0,
	HEARTBEAT_E_INVALID_ARG     = -1,
	HEARTBEAT_E_PLIST_ERROR     = -2,
	HEARTBEAT_E_MUX_ERROR       = -3,
	HEARTBEAT_E_SSL_ERROR       = -4,
	HEARTBEAT_E_NOT_ENOUGH_DATA = -5,
	HEARTBEAT_E_TIMEOUT         = -6,
	HEARTBEAT_E_UNKNOWN_ERROR   = -256
}

struct heartbeat_client_private; /**< \private */
alias heartbeat_client_t = heartbeat_client_private*; /**< The client handle. */

/* Interface */

/**
 * Connects to the heartbeat service on the specified device.
 *
 * @param device The device to connect to.
 * @param service The service descriptor returned by lockdownd_start_service.
 * @param client Pointer that will point to a newly allocated
 *     heartbeat_client_t upon successful return. Must be freed using
 *     heartbeat_client_free() after use.
 *
 * @return HEARTBEAT_E_SUCCESS on success, HEARTBEAT_E_INVALID_ARG when
 *     client is NULL, or an HEARTBEAT_E_* error code otherwise.
 */
heartbeat_error_t heartbeat_client_new(idevice_t device, lockdownd_service_descriptor_t service, heartbeat_client_t * client);

/**
 * Starts a new heartbeat service on the specified device and connects to it.
 *
 * @param device The device to connect to.
 * @param client Pointer that will point to a newly allocated
 *     heartbeat_client_t upon successful return. Must be freed using
 *     heartbeat_client_free() after use.
 * @param label The label to use for communication. Usually the program name.
 *  Pass NULL to disable sending the label in requests to lockdownd.
 *
 * @return HEARTBEAT_E_SUCCESS on success, or an HEARTBEAT_E_* error
 *     code otherwise.
 */
heartbeat_error_t heartbeat_client_start_service(idevice_t device, heartbeat_client_t * client, const char* label);


/**
 * Disconnects a heartbeat client from the device and frees up the
 * heartbeat client data.
 *
 * @param client The heartbeat client to disconnect and free.
 *
 * @return HEARTBEAT_E_SUCCESS on success, HEARTBEAT_E_INVALID_ARG when
 *     client is NULL, or an HEARTBEAT_E_* error code otherwise.
 */
heartbeat_error_t heartbeat_client_free(heartbeat_client_t client);

/**
 * Sends a plist to the service.
 *
 * @param client The heartbeat client
 * @param plist The plist to send
 *
 * @return HEARTBEAT_E_SUCCESS on success,
 *  HEARTBEAT_E_INVALID_ARG when client or plist is NULL
 */
heartbeat_error_t heartbeat_send(heartbeat_client_t client, plist_t plist);

/**
 * Receives a plist from the service.
 *
 * @param client The heartbeat client
 * @param plist The plist to store the received data
 *
 * @return HEARTBEAT_E_SUCCESS on success,
 *  HEARTBEAT_E_INVALID_ARG when client or plist is NULL
 */
heartbeat_error_t heartbeat_receive(heartbeat_client_t client, plist_t* plist);

/**
 * Receives a plist using the given heartbeat client.
 *
 * @param client The heartbeat client to use for receiving
 * @param plist pointer to a plist_t that will point to the received plist
 *      upon successful return
 * @param timeout_ms Maximum time in milliseconds to wait for data.
 *
 * @return HEARTBEAT_E_SUCCESS on success,
 *      HEARTBEAT_E_INVALID_ARG when client or *plist is NULL,
 *      HEARTBEAT_E_NOT_ENOUGH_DATA when not enough data
 *      received, HEARTBEAT_E_TIMEOUT when the connection times out,
 *      HEARTBEAT_E_PLIST_ERROR when the received data cannot be
 *      converted to a plist, HEARTBEAT_E_MUX_ERROR when a
 *      communication error occurs, or HEARTBEAT_E_UNKNOWN_ERROR
 *      when an unspecified error occurs.
 */
heartbeat_error_t heartbeat_receive_with_timeout(heartbeat_client_t client, plist_t* plist, uint timeout_ms);

