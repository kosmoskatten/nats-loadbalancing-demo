{-# LANGUAGE OverloadedStrings #-}
-- | A summy service which can be load balanced by NATS. The service
-- can create items, and once created an item will tickle its peer
-- once every second.
module Main
    ( main
    ) where

import Control.Concurrent (threadDelay)
import Control.Monad (forever, void)
import Data.String.Conv (toS)
import Network.Nats
import System.Environment (getArgs)

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

main :: IO ()
main = do
    -- Get the URI for the NATS server from the command line.
    [natsUri] <- map BS.pack <$> getArgs
    runNatsClient defaultSettings natsUri $ \conn -> do
        let payload = "I'm tickling you :-)"

        -- Once connected to the NATS server subscribe to the topic
        -- of creating an item. Creating items is part of the queue group
        -- "ITEMPOOL". All subscribers of this queue group will be load
        -- balanced through random selection by the NATS server.
        void $ subAsync conn "item.create.*" (Just "ITEMPOOL")
                        (createItem conn payload)

        -- Just keeping the main thread alive.
        stayAlive

-- | Handler for the creation of topics, the topic will look like:
-- item.create.<itemId>
-- As payload the create message will carry the id of the item's peer.
createItem :: Connection -> LBS.ByteString -> NatsMsg -> IO ()
createItem conn payload (NatsMsg topic _ _ peer) = do
    let itemId      = wildCard
        tickleTopic = "item." `BS.append` itemId `BS.append` ".tickle"
        peerTopic   = "item." `BS.append` (toS peer) `BS.append` ".tickle"

    BS.putStrLn $ "createItem " `BS.append` itemId

    -- Subscribe to tickles. Just do WHNF of the payload to avoid compile
    -- optimizations of the handler.
    void $ subAsync' conn tickleTopic $
        \(NatsMsg _ _ _ payload) -> payload `seq` return ()

    -- | Now, for the rest of the life of this thread, continously send
    -- tickles to the peer item.
    forever $ do
        pub' conn peerTopic payload
        threadDelay period
    where
      wildCard = BS.split '.' topic !! 2
      period   = 100000

-- | Just to keep the main thread alive.
stayAlive :: IO ()
stayAlive = forever $ threadDelay 10000000
