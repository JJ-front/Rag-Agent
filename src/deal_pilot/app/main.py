from contextlib import asynccontextmanager

from fastapi import FastAPI
from deal_pilot.app.experiment_webhook import router as experiment_router
from deal_pilot.app.alert_webhook import router as alert_router
from deal_pilot.config.feishu_settings import feishu_settings
from deal_pilot.event.listener import start_feishu_events, cancel_feishu_events
import asyncio


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 飞书事件监听是可选的：只有显式开启才启动，避免没配飞书时阻塞 Agent。
    if feishu_settings.events_enabled:
        await start_feishu_events()
    try:
        yield
    finally:
        if feishu_settings.events_enabled:
            await asyncio.to_thread(cancel_feishu_events)


app = FastAPI(lifespan=lifespan)
app.include_router(experiment_router)
app.include_router(alert_router)
