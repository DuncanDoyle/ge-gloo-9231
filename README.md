# Gloo-9231 Reproducer

## Installation

Add Gloo EE Helm repo:
```
helm repo add glooe https://storage.googleapis.com/gloo-ee-helm
```

Export your Gloo Edge License Key to an environment variable:
```
export GLOO_EDGE_LICENSE_KEY={your license key}
```

Install Gloo Edge:
```
cd install
./install-gloo-edge-enterprise-with-helm.sh
```

> NOTE
> The Gloo Edge version that will be installed is set in a variable at the top of the `install/install-gloo-edge-enterprise-with-helm.sh` installation script.

## Setup the environment

Run the `install/setup.sh` script to setup the environment:
- Deploy Keycloak
- Deploy the OAuth Authorization Code Flow AuthConfig.
- Deploy the VirtualServices
- Deploy the HTTPBin service

```
./setup.sh
```

Run the `install/k8s-coredns-config.sh` script to patch K8S coreDns service to route `keycloak.example.com` to the Gloo Edge `gateway-proxy`. In this example this is needed to allow the AuthConfig that points to Keycloak to resolve `keycloak.example.com` and to route to Keycloak via the Gateway.

```
./k8s-coredns-config.sh
```

## Setup Keycloak

Run the `keycloak.sh` script to create the OAuth clients and user accounts required to run the demo. This script will create an OAuth client for our web-application to perform OAuth Authorization Code Flow, an OAuth Client (Service Account) for Client Credentials Grant Flow (not used in this example), and 2 user accounts (`user1@example.com` and `user2@solo.io`).

```
./keycloak.sh
```

## Reproducer

Navigate to http://api.example.com/forms/post. You will be redirected to Keycloak to login. Login with:

```
Username: user1@example.com
Password: password
```

This will:
- Create get you an authorization code
- Gloo will exchange the authorization code for an id-token, access-token and refresh token.
- Gloo will create a session in Redis in which it will store the tokens.
- Gloo sets a session cookie on the response to the client, pointing at the session in Redis. We've configured the `maxAge` of this cookie to 30 seconds.
- Client is redirected to the form.


In the form, in the "Customer name" field, enter "Kermit" and click on the "Submit order" button. You will get a response that shows the post-request that was made to the HTTPBin application. Press the back button in your browser to go back to the form, wait 30 seconds for the session cookie to reach its "maxAge" and submit the form again. You will now get a "Method not allowed" error on your screen.

What is happening is that because the session cookie has expired, Gloo needs to retrieve a new set of tokens and create a new session. For that it redirects (302) the client to Keycloak. Since the session with Keycloak is still valid, Keycloak issues a new authorization code, and redirects (302)the client to the `/callback` endpoint. The callback endpoint exchanges the authorization code for a new set of tokens, after which it redirects (302) the client back to `http://api.example.com/post` (the URL to which the form POSTS the HTTP request. The problem is that the browser uses a `GET` method when it redirects to that endpoint, and the endpoint only supports a `POST` method.

Gloo redirects the client to the originally requested endpoint by storing the URL in the `state` JWT that is send to Keycloak and is passed on all subsequent redirects. That JWT however does not contain the HTTP Method that was used to access the given URL. Another problem is that, even if we would store the Method used in the original request, we can't simply redirect with a POST (maybe using a 307 response code), as we would also need to store the original POST data in one way or another.


## Conclusion
When the Gloo session cookie expires, Gloo redirects the client to Keycloak, which after login, redirects the client to the `/callback` endpoint, which redirects the client to the originally requested URL. The client uses an HTTP `GET` method for this. If the original method that was fired after the session expired was a `POST`, we don't redirect the client with a `POST` request (possibly with a 307).

A question is how we could actually do this. We would not only need to store the endpoint in the `state` JWT, but also the HTTP method AND the `POST` request data.